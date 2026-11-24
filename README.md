<img  align="left" width="150" style="float: left;" src="https://www.upm.es/sfs/Rectorado/Gabinete%20del%20Rector/Logos/UPM/CEI/LOGOTIPO%20leyenda%20color%20JPG%20p.png">
<img  align="right" width="60" style="float: right;" src="https://www.dit.upm.es/images/dit08.gif" >


<br/><br/>


# Laboratorio 5: Credenciales efímeras con Vault

*Curso de Identidad Digital, Autenticación y Autorización — Módulo 4: Gestión de accesos
privilegiados e identidades de máquina.*

## Objetivos

En todos los laboratorios anteriores quien se autenticaba era una persona. Sin embargo, buena parte
de los accesos de una organización los realizan **máquinas**: scripts, aplicaciones o tareas de
integración continua que necesitan hablar con una base de datos o con una API. La respuesta habitual
es una credencial fija guardada en algún sitio (un fichero `.env`, un secreto del sistema de CI/CD)
que vive meses o años sin cambiar. Esta práctica explora la alternativa que propone **HashiCorp
Vault**: no guardar ningún secreto, porque ningún secreto dura más que la tarea que lo necesita. La
credencial se pide, se usa y desaparece sola.

Al finalizar la práctica, el estudiante será capaz de:

- Explicar qué es una bóveda de secretos y por qué Vault arranca **sellado**.
- Inicializar y desellar Vault mediante varias claves independientes.
- Configurar Vault para que genere usuarios de base de datos **bajo demanda**, con un tiempo de vida
  limitado.
- Distinguir entre la **expiración** de una credencial y su **revocación**.
- Relacionar las credenciales efímeras con el problema de las identidades de máquina (NHI).

## Dependencias

Para realizar la práctica, el alumno deberá tener instalado en su ordenador:

- **Docker** y **Docker Compose** ([instalación](https://docs.docker.com/get-docker/)).
- Los puertos **8200** (Vault) y **8083** (Adminer) libres.
- Cualquier navegador moderno (Chrome, Edge, Chromium o Firefox).
- Un sitio donde apuntar cinco claves y un *token* (un papel sirve). Vault los muestra una sola vez y
  se necesitan varias veces durante la práctica.

La práctica es independiente de los laboratorios anteriores: no usa Keycloak.

## Descripción de la práctica

El escenario se compone de tres piezas. **PostgreSQL** es la base de datos que se quiere proteger;
contiene una tabla de ejemplo, `inventario`. **Adminer** es un cliente SQL web que hace aquí el
papel de *la aplicación* que necesita acceder a la base de datos. Y **Vault** es la bóveda: guarda la
credencial del superusuario de PostgreSQL y, cada vez que alguien se lo pide, crea con ella un
usuario nuevo, de vida corta, que borra él mismo al terminar ese plazo.

```mermaid
sequenceDiagram
  participant A as Alumno (navegador)
  participant V as Vault :8200
  participant P as PostgreSQL
  participant D as Adminer :8083
  A->>V: Pide credenciales (rol app-readonly)
  V->>P: CREATE ROLE v-...-xyz VALID UNTIL +60 s
  V-->>A: Usuario y contraseña nuevos + lease de 60 s
  A->>D: Inicia sesión con ese usuario
  D->>P: SELECT * FROM inventario
  Note over V,P: Al caducar o revocar el lease
  V->>P: DROP ROLE v-...-xyz
```

Cada credencial que entrega Vault va asociada a un **lease** (un "alquiler"): un identificador con
una duración (*TTL*, *time to live*). Al acabar el TTL, Vault borra el usuario. El administrador
puede además **revocar** un lease antes de tiempo.

Vault se ejecuta aquí en su modo **real**, no en el modo de desarrollo que suele verse en los
tutoriales rápidos. Eso implica que guarda sus datos en disco y que arranca **sellado**: nadie, ni
siquiera quien tenga acceso de administrador al servidor, puede leer su contenido sin antes
desellarlo, y para desellarlo hacen falta varias claves distintas. Lo único que se ha simplificado es
el cifrado de las comunicaciones (TLS), que no aporta nada a lo que se quiere mostrar.

PostgreSQL no publica ningún puerto: solo se llega a él a través de Adminer, por la red interna de
Docker.

---

## 1. Puesta en marcha

Copie el fichero de configuración y levante el entorno:

```bash
cp .env.example .env
docker compose up -d
```

Compruebe que todo funciona:

- `http://localhost:8200` muestra la pantalla **Let's set up the initial set of root keys**: Vault
  detecta que no está inicializado y lo pide antes de permitir nada más.
- `http://localhost:8083` muestra el inicio de sesión de Adminer. No entre todavía: aún no existe
  ninguna credencial que usar.

---

## 2. Inicialización y desellado

1. **Inicializar:** en esa pantalla, **Key shares** = `5` y **Key threshold** = `3` → **Initialize**.

   Vault muestra el **token root** y las **cinco claves de desellado**, cada una oculta tras un botón.
   **Cópielas ahora** (o pulse **Download keys**): es la única vez que Vault las enseña.

2. **Desellar:** **Continue to Unseal** → pantalla **Unseal Vault** → pegue una clave en **Unseal Key
   Portion** → **Unseal**. El progreso avanza (`1/3`, `2/3`…). Repita con **tres claves distintas**
   de las cinco. Al llegar a `3/3`, Vault se desella y da paso a la consola. Si pide iniciar sesión,
   use el token root.

> **Pregunta 2.1.** ¿Por qué hacen falta tres claves de cinco para desellar Vault, y no basta con una
> sola? ¿Qué impide esto en una organización real?

---

## 3. Configuración del acceso efímero

3. **Habilitar el motor de bases de datos:** menú lateral → **Secrets engines** → **Enable new
   engine** → **Database** → **Enable Engine** (deje la ruta por defecto, `database/`).

4. **Configurar la conexión con PostgreSQL:** dentro de `database/`, pulse **Connect a database**.
   - **Database plugin**: `PostgreSQL`. El resto de campos aparece después de elegirlo.
   - **Connection name**: `appdb`.
   - **Connection URL**:
     ```
     postgresql://{{username}}:{{password}}@postgres:5432/appdb?sslmode=disable
     ```
     Las llaves dobles se escriben **literalmente**: es una plantilla que Vault rellena él mismo.
   - **Username** y **Password** (dos campos aparte, al final del formulario): `appadmin` /
     `appadmin`, los de `.env`. Es el superusuario que Vault usará para crear y borrar usuarios.
   - **Create database**.

5. **Rotación de la credencial root:** Vault pregunta a continuación **Rotate your root
   credentials?**. Elija **Rotate and enable**. Vault cambia la contraseña de `appadmin` por una que
   solo él conoce, y la de `.env` deja de servir.

> **Pregunta 3.1.** Tras la rotación, nadie conoce la contraseña del superusuario `appadmin`. ¿Qué
> implica esto? Si un administrador necesita entrar en la base de datos con todos los privilegios,
> ¿cómo podría hacerlo sin volver a tener una contraseña fija?

6. **Crear el rol:** pestaña **Roles** → **Create role**.
   - **Role name**: `app-readonly`. **Database name**: `appdb`.
   - **Type of role**: `dynamic`. Hasta que no se elige, el formulario no muestra los campos
     siguientes.
   - **Generated credentials's Time-To-Live (TTL)**: `60` segundos. **Max TTL**: `120` segundos.
   - **Creation Statements**, lo que Vault ejecuta para crear cada usuario:
     ```sql
     CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
     GRANT CONNECT ON DATABASE appdb TO "{{name}}";
     GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
     ```
   - **Revocation Statements**, lo que ejecuta para borrarlo:
     ```sql
     REASSIGN OWNED BY "{{name}}" TO appadmin;
     DROP OWNED BY "{{name}}";
     SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = '{{name}}';
     DROP ROLE IF EXISTS "{{name}}";
     ```
   - Guarde el rol.

---

## 4. Credenciales bajo demanda

7. **Pedir credenciales:** abra el rol `app-readonly` → **Generate credentials**. Vault muestra un
   `Username`, un `Password`, un `Lease ID` y `Lease Duration: 60`. Cópielos: no se pueden volver a
   ver.

8. **Usarlas:** en Adminer (`http://localhost:8083`):
   - **Motor de base de datos** (*System*): `PostgreSQL`. Por defecto viene MySQL.
   - **Servidor**: `postgres` (ya viene relleno).
   - **Usuario** y **Contraseña**: los que acaba de dar Vault.
   - **Base de datos**: `appdb` → **Login**.

   En el menú lateral, pulse **registros inventario** (en inglés, *select inventario*): aparecen
   las tres filas de ejemplo. El acceso funciona con un usuario que hace un minuto no existía.

9. **Esperar al TTL:** cuando hayan pasado 60 segundos desde el paso 7, pulse cualquier enlace de
   Adminer (por ejemplo, otra vez **registros inventario**). No hace falta cerrar la sesión: Adminer
   abre una conexión nueva en cada clic, y esta vez falla y le devuelve al inicio de sesión:
   ```
   FATAL:  password authentication failed for user "v-root-app-read-..."
   ```
   Vault ha borrado el usuario de PostgreSQL al caducar el lease, sin que nadie se lo pida.

10. **Pedir credenciales otra vez** (repita el paso 7) y compruebe que el `Username` es distinto: cada
    petición crea un usuario nuevo.

<details>
<summary><strong>En detalle (opcional):</strong> ver nacer y morir los usuarios desde dentro de PostgreSQL. No es necesario para continuar.</summary>

No hace falta el superusuario: cualquier usuario puede consultar la lista de usuarios. Con la sesión
del paso 8 abierta, y antes de que pase el minuto, vaya a Adminer → **Comando SQL** y ejecute:

```sql
SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolname LIKE 'v-%';
```

Aparece su propio usuario, con la fecha de caducidad que fija el `VALID UNTIL` de las Creation
Statements. Repita la consulta entrando con las credenciales del paso 10: el usuario anterior ya no
está, y solo aparece el nuevo.

</details>

> **Pregunta 4.1.** El usuario ya no existe en PostgreSQL, pero el error del paso 9 dice "password
> authentication failed", no "el usuario no existe". ¿Por qué cree que PostgreSQL responde así?

> **Pregunta 4.2.** Supóngase que alguien intercepta una de estas credenciales, por ejemplo porque
> aparece en un fichero de log. ¿Durante cuánto tiempo le sirve? Compárelo con una contraseña fija
> guardada en un `.env`.

---

## 5. Verificación: revocar una credencial en uso

Esperar al TTL solo demuestra que un inicio de sesión *nuevo* falla. Este apartado comprueba algo
distinto: que el administrador puede **revocar** una credencial antes de tiempo y cortar incluso una
conexión que ya está en marcha. Todo debe hacerse dentro de los 60 segundos del TTL, así que conviene
tener Vault y Adminer abiertos en dos pestañas antes de empezar.

> **Si no le da tiempo:** suba el TTL del rol. En Vault, abra el rol `app-readonly` → **Edit role** y
> ponga, por ejemplo, **TTL** = `300` segundos y **Max TTL** = `600`. El cambio solo afecta a las
> credenciales que se pidan a partir de entonces: pida unas nuevas. Vale también para el apartado 4.

1. **Pida credenciales nuevas** (paso 7), apunte el `Lease ID` y **entre con ellas en Adminer**
   (paso 8).
2. **Lance una consulta lenta**, para tener algo en marcha que cortar: Adminer → **Comando SQL**
   (*SQL command*) →
   ```sql
   SELECT pg_sleep(45), * FROM inventario;
   ```
   → **Ejecutar**. La pestaña se queda cargando: déjela así.
3. **En la pestaña de Vault, revoque ese lease:** **Access** → **Leases** → `database/` → `creds/` →
   `app-readonly/` → el identificador que coincide con el final del `Lease ID` apuntado → **Revoke
   lease** → confirme.
4. **Vuelva a la pestaña de Adminer.** La consulta se ha cortado sin esperar a los 45 segundos:
   ```
   Error in query (7): FATAL:  terminating connection due to administrator command
   ```
   Si intenta volver a entrar con esas credenciales, `password authentication failed`: el usuario ya
   no existe.

> **Pregunta 5.1.** ¿Para qué sirve la línea `pg_terminate_backend` de las Revocation Statements, si
> `DROP ROLE` ya borra el usuario? ¿Qué habría pasado en este apartado sin ella?

> **Pregunta 5.2.** Las claves de API y las contraseñas guardadas en ficheros de configuración o en
> sistemas de CI/CD son uno de los grandes problemas de las identidades de máquina (NHI). ¿Cómo lo
> resuelve el modelo que se ha montado en esta práctica?

---

## Resolución de problemas

- **Ha perdido el token root o las claves de desellado.** Sin al menos tres de las cinco claves, ese
  Vault queda sellado para siempre. Hay que empezar de cero: `docker compose down -v && docker compose
  up -d`, y repetir desde el apartado 2.
- **Vault vuelve a estar sellado** tras reiniciar el contenedor (o el ordenador). Es su
  comportamiento normal: repita el paso 2 con tres claves. El motor, la conexión y el rol siguen
  configurados.
- **La consola de Vault vuelve a pedir el token** al recargar la página o escribir una URL a mano. No
  es que se haya sellado (en ese caso la pantalla sería **Unseal**, no **Sign in**): pegue de nuevo el
  token root. Moverse siempre con el menú lateral evita el problema.
- **Falla el paso 4 (Create database) con `connection refused`.** Revise la **Connection URL**: el
  servidor es `postgres`, no `localhost`, y debe terminar en `?sslmode=disable`.
- **`password authentication failed for user "[password]"`** al guardar la conexión: la contraseña
  del superusuario no es correcta. Vault oculta la contraseña en sus errores como `[password]`, y
  como aquí usuario y contraseña coinciden, oculta también el nombre. Compruebe que **Username** y
  **Password** son `appadmin` / `appadmin` y que la plantilla con llaves está solo en la URL. Si ya
  había rotado la credencial (paso 5) y está creando la conexión otra vez, `appadmin` / `appadmin`
  ya no sirve: avise al profesor, o empiece de cero con `docker compose down -v && docker compose
  up -d`.
- **Adminer muestra un error que menciona MySQL:** el **Motor de base de datos** sigue en
  `MySQL / MariaDB`. Cámbielo a `PostgreSQL`.
- **Las credenciales caducan antes de terminar el paso:** suba el TTL y el Max TTL del rol (vea la
  nota del apartado 5) y pida credenciales nuevas.
- **La revocación del apartado 5 no corta la consulta:** faltan las Revocation Statements del paso 6.
  Edite el rol y añádalas.
- Para reiniciar el entorno desde cero (se pierde toda la configuración de Vault y habrá que
  inicializarlo de nuevo): `docker compose down -v && docker compose up -d`.
