# Altair · Ansible

Configuración declarativa del VPS Ubuntu: Docker, usuarios, firewall, aplicaciones,
proxy, Netdata y backups Restic en Cloudflare R2.

## Estructura

| Ruta | Responsabilidad |
| --- | --- |
| `inventory/hosts.yml` | Inventario único; conexión al host `target` del grupo `servers` |
| `inventory/group_vars/all/` | Configuración del entorno y archivos cifrados de Vault |
| `roles/` | Roles reutilizables con tareas, defaults, handlers y plantillas |
| `roles/apps/` | Selección del catálogo y plantillas específicas de cada app |
| `roles/compose/` | Directorios, red, configuración y reconciliación de Compose |
| `playbooks/` | Entradas operativas; `site.yml` aplica la configuración completa |
| `proxy_hosts/` | Dominios y configuración de Nginx Proxy Manager |
| `scripts/` | Validación, despliegue y actualización de versiones |
| `tests/` | Datos ficticios, regresiones y prueba de idempotencia con Docker |

## Preparación local

Ejecuta desde la raíz del repositorio con Python 3.12:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
scripts/check.sh
```

`requirements.txt` fija las versiones de las herramientas principales;
`requirements.yml` fija las colecciones. Las dependencias transitivas de Python
las resuelve pip. CI usa los mismos archivos.

Las pruebas usan variables ficticias y no descifran los archivos de producción.
CI añade `docker compose config`, actionlint y dos ejecuciones de un stack desechable
para comprobar que la segunda ejecución del rol Compose tiene `changed=0`.

## Variables y secretos

| Archivo | Qué editar |
| --- | --- |
| `all.yml` | Identidad, usuario SSH, puerto y estrategia de bootstrap |
| `paths.yml` | Raíces de `/srv`, stacks, datos y configuración |
| `apps.yml` | Catálogo de apps, imágenes, directorios y configuración de n8n |
| `network.yml` | Puertos, bind de administración, contacto y rutas de proxy |
| `users.yml` | Usuarios administrados, grupos y claves públicas |
| `backup.yml` | Repositorio R2, rutas y exclusiones de respaldo |
| `data-services.yml` | PostgreSQL opcional, deshabilitado inicialmente |
| `vault.yml`, `data-services.vault.yml` | Secretos cifrados existentes |

Los defaults reutilizables pertenecen al rol; las decisiones de este servidor
pertenecen al inventario. Se mantienen los nombres actuales de los secretos:
`server_ip`, `domain_name`, `admin_user_ssh_pubkey`, `npm_identity`, `npm_secret`,
`vault_postgres_password`, `vault_restic_password`, `vault_backup_aws_access_key_id`
y `vault_backup_aws_secret_access_key`. No se necesita volver a cifrarlos.

```bash
ansible-vault edit inventory/group_vars/all/vault.yml
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass --check
```

`--check` requiere acceso SSH y facts del servidor, pero no aplica cambios.
En un host nuevo algunas dependencias aún no existen: Compose omite la ejecución
si el archivo del proyecto todavía no existe. Para NPM se validan las definiciones,
pero se omite toda reconciliación de API y emisión de certificados. No es una
simulación completa de un primer bootstrap ni de la API de NPM.

## Operación

```bash
# Servidor nuevo: crear el usuario antes de cerrar acceso root.
ansible-playbook playbooks/bootstrap-init.yml --ask-vault-pass
# Tras verificar SSH con el usuario administrado:
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass

# Una app, varias o todas; alias uptime-kuma aceptado.
scripts/deploy-app.sh portfolio target playbooks/apps.yml --ask-vault-pass --check
scripts/deploy-app.sh portfolio,n8n target playbooks/apps.yml --ask-vault-pass
scripts/deploy-app.sh all target playbooks/apps.yml --ask-vault-pass

# Reconciliación completa o por responsabilidad.
ansible-playbook playbooks/site.yml --ask-vault-pass
ansible-playbook playbooks/backup.yml --ask-vault-pass
ansible-playbook playbooks/proxy-hosts.yml --ask-vault-pass
```

El rol Docker usa la distribución Ubuntu y arquitectura detectadas, con repositorio
firmado, y retira la entrada heredada de Focal. Los upgrades generales del sistema
requieren `-e base_upgrade_packages=true`. El rol `users` administra pertenencia a
Docker después de instalarlo; `security` administra el firewall.

## Agregar o actualizar aplicaciones

1. Añade una clave a `apps` con `deploy_dir`, `image_repo`, `image_tag` y
   `container_name`, y su plantilla en
   `roles/apps/templates/<clave>/docker-compose.yml.j2`.
2. Si necesita directorios con permisos específicos, declara `directories`
   con `path`, `owner`, `group` y `mode`, como n8n. No se cambian permisos
   recursivamente sobre datos existentes.
3. Agrega el proxy en `proxy_hosts/` si corresponde. Ejecuta `scripts/check.sh`.
4. Crea un PR. No necesitas otro rol ni modificar una lista de apps en el workflow.

`enabled: false` significa omitir la app: no detiene contenedores ni elimina datos.
Los proyectos conservan sus nombres derivados del directorio y no eliminan huérfanos.
Compose espera contenedores en ejecución y, cuando la imagen define un healthcheck,
sanos; esto no sustituye una prueba funcional de la aplicación.

```bash
scripts/update-app-tag.sh uptime-kuma 2.1.3
scripts/update-app-tag.sh portfolio abcdef0123456789
scripts/open-deploy-pr.sh portfolio abcdef0123456789
```

Los SHA hexadecimales de 7–40 caracteres reciben prefijo `sha-`; los tags de versión
se conservan. El parser YAML rechaza apps desconocidas, duplicados y tags inválidos.
`open-deploy-pr.sh` requiere árbol limpio y `gh` autenticado; crea una rama desde
`origin/main`, sin sobrescribir ramas existentes. Para generar PR desde otro workflow
usa credenciales que permitan activar los checks del nuevo PR; los eventos creados
con el `GITHUB_TOKEN` predeterminado pueden no iniciar otros workflows.

La política predeterminada `pull: missing` conserva imágenes existentes para tags
mutables como `latest`. Para actualizar uno explícitamente usa
`-e apps_pull_policy=always`. Para rollback reproducible fija versiones o tags SHA.
Este refactor no cambia las versiones de las aplicaciones desplegadas.

## CI/CD en GitHub Actions

- **Ansible CI**: corre en cada PR y en `main`; sin secretos de producción.
- **Deploy App**: selección de una, varias o todas las apps, con `check=true` inicialmente.
- **Update Infra Deploy**: selección manual de apps, infraestructura, backups,
  proxies, bases de datos, Netdata o todo. Con `ALTAIR_AUTO_DEPLOY=true`, un push
  relevante a `main` reconcilia `site.yml` completo, incluyendo múltiples apps.
- **Ansible Deploy (Reusable)**: vuelve a validar el mismo commit antes de desplegar;
  solo admite `main`, rechaza una revisión superada, usa el entorno `altair` y
  serializa todas las ejecuciones mediante el grupo `altair-production`.

Configura estos secretos en el repositorio o en el entorno `altair`:

| Secreto | Contenido |
| --- | --- |
| `ANSIBLE_VAULT_PASSWORD` | Contraseña de Vault |
| `ANSIBLE_SSH_PRIVATE_KEY` | Clave privada del usuario administrado |
| `ANSIBLE_SSH_KNOWN_HOSTS` | Clave pública del host SSH, obtenida y verificada por un canal confiable |

La clave del host es obligatoria. Los secretos se escriben con permisos `0600` en
el directorio temporal del runner y se eliminan incluso si el despliegue falla.
Los parámetros se pasan por variables de entorno o argumentos, sin interpolarlos
como código shell. El entorno puede tener revisores obligatorios y limitarse a `main`;
estas reglas se configuran en GitHub, no se crean por declarar `environment` en YAML.

GitHub mantiene como máximo una ejecución pendiente por grupo de concurrencia:
puede sustituir pendientes. La reconciliación completa de la revisión más reciente
aplica el estado deseado acumulado. Si una revisión antigua se rechaza, ejecuta de
nuevo el workflow sobre el `main` actual; no reejecutes un commit superado.

La interfaz reutilizable `discord-notify.yml` se conserva para consumidores externos.
El despliegue ya no depende de una notificación ni la invoca automáticamente.

## Migración y rollback

Antes de activar el CD automático, sigue [docs/migration.md](docs/migration.md).
