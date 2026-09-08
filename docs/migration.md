# Migración del refactor de Altair

El PR cambia la automatización. No aplica cambios al VPS al abrirse ni fusiona ramas.
`ALTAIR_AUTO_DEPLOY` debe permanecer sin definir o en `false` durante la revisión inicial.

## Compatibilidad

| Antes | Ahora |
| --- | --- |
| `playbooks/roles/` | `roles/`, resuelto por `ansible.cfg` |
| Roles separados de portfolio, n8n, npm, Portainer y Uptime Kuma | Catálogo `apps` + `apps` + `compose` |
| `backup-tools`, `data-services`, `proxy-hosts`, `user-management` | `backup`, `data_services`, `proxy_hosts`, `users` |
| `--tags uptime-kuma` sobre apps.yml | `scripts/deploy-app.sh uptime-kuma ...` o `-e '{"apps_selected":["uptime_kuma"]}'` |
| Dos inventarios | `inventory/hosts.yml`; se elimina el INI con host `REDACTED` |
| Dominio n8n fijo | `n8n_subdomain` + `domain_name`; `.env` es consumido por Compose |
| Puertos 81 y 9000 en todas las interfaces | Bind `127.0.0.1` por defecto; NPM sigue alcanzando servicios por red Docker |
| Deploy App con `limit`, `playbook`, `image_tag`, `environment` | `app` y `check`; host/playbook/entorno controlados por el workflow |
| Update Infra con `app`, `image_tag` | `scope` y `check`; imagen definida exclusivamente en el catálogo |
| Deploy automático solo para un cambio de tag | Reconciliación completa después de CI, activada con variable de repositorio |

Se mantienen `portfolio.yml`, `uptimekuma.yml`, los nombres y rutas de datos y
proyectos Compose, los secretos Vault cifrados, las imágenes existentes, la red
`proxy`, PostgreSQL deshabilitado y los backups Restic en R2. Se conservan retención,
horario y exclusiones; un cambio del timer ahora reinicia el timer para aplicarse.

## Primera aplicación

1. Comprueba el CI del PR y configura los tres secretos SSH/Vault documentados.
   Verifica el acceso del usuario administrado y una copia recuperable de los datos.
2. Configura `altair` como entorno de GitHub y, si lo necesitas, revisores y restricción
   a `main`. Haz obligatorio el check **Validate Ansible and Compose** en la protección
   de la rama. Estos ajustes de GitHub no se modifican desde el repositorio.
3. Comprueba que `domain_name` corresponde al dominio actual de n8n. El antiguo
   valor estaba escrito directamente en sus plantillas. Ajusta `n8n_proxy_hops`
   a la cantidad real de proxies confiables.
4. Revisa `npm_admin_bind` y `portainer_bind`. Si accedes a sus puertos directamente
   por Tailscale, configura la IP de esa interfaz; con el valor inicial usa un túnel
   SSH o el proxy. La metadata heredada `onlyTailScale` por sí sola no impone una
   política de acceso; revisa las ACL de NPM/Tailscale por separado.
5. Fusiona el PR tras revisión y ejecuta **Update Infra Deploy**, `scope=infrastructure`,
   `check=true`. Revisa los cambios de repositorio Docker y SSH. El primer check de
   un servidor virgen puede fallar por paquetes, usuarios o servicios aún inexistentes.
6. Aplica infraestructura con `check=false`; después apps, backup y proxy por separado.
   Revisa salud de n8n, Uptime Kuma, Portainer y portfolio, resolución de dominios y TLS,
   y `sudo restic-cli status` / `sudo restic-cli snapshots`.
7. Activa `ALTAIR_AUTO_DEPLOY=true` para reconciliar automáticamente cambios futuros
   de `main`. Este flujo completo también configura Netdata, usuarios, firewall y
   proxies; no requiere ni ejecuta bootstrap inicial como root.

CI valida estructura, módulos, sintaxis, scripts, renderizado y Compose con datos
ficticios, e idempotencia del rol compartido en Docker. No valida conectividad SSH,
credenciales reales, el estado de bases de datos, acceso a R2 ni emisión de certificados.
La API de NPM necesita una comprobación real tras aplicar; `--check` la omite.

## Recuperación

Desactiva `ALTAIR_AUTO_DEPLOY` antes de revertir una migración fallida. Revierte el
commit problemático mediante otro PR y despliega desde el `main` vigente. Para una
imagen, restaura su tag anterior en `apps.yml`; evita `latest` si necesitas reproducir
exactamente una versión. Un downgrade de aplicación puede requerir restaurar datos
si esa versión migró su base de datos: cambiar el tag no revierte una migración.

No ejecutes `docker compose down --volumes` sobre stacks de producción. Este refactor
no borra volúmenes, no mueve datos persistentes y no cambia la clave de cifrado de n8n.
Si los datos existentes de n8n tienen propietarios incorrectos, corrígelos tras revisar
su estado: ya no se hace un `chown` recursivo en cada despliegue.

## Referencias de implementación

- [Ansible Compose v2](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_compose_v2_module.html)
- [Cambios de templating en Ansible 2.19](https://docs.ansible.com/projects/ansible/latest/porting_guides/porting_guide_core_2.19.html)
- [Workflows reutilizables y secretos de entorno](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
