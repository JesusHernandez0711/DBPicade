# PICADE - Módulo de Autenticación y Gestión de Usuarios

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    CAPA DE PRESENTACIÓN                      │
│  login.blade.php ──── register.blade.php                     │
│  (Glassmorphism)       (Formulario de auto-registro)         │
│         │                       │                            │
│         └───────┬───────────────┘                            │
│                 ▼                                             │
│         ┌─────────────┐    ┌──────────────────┐              │
│         │AuthController│    │  UserController  │              │
│         │             │    │   (CRUD Admin)   │              │
│         │ • login     │    │ • index (Grid)   │              │
│         │ • register  │    │ • store (Alta)   │              │
│         │ • logout    │    │ • update (Edit)  │              │
│         └──────┬──────┘    │ • toggleEstatus  │              │
│                │           │ • destroy        │              │
│                │           │ • miPerfil       │              │
│                │           └────────┬─────────┘              │
│                └────────┬───────────┘                        │
│                         ▼                                    │
│              ┌─────────────────┐                             │
│              │   User Model    │                             │
│              │  (Eloquent +    │                             │
│              │   SP Wrappers)  │                             │
│              └────────┬────────┘                             │
│                       ▼                                      │
├─────────────────────────────────────────────────────────────┤
│                    CAPA DE DATOS (MySQL)                      │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────┐          │
│  │  Usuarios    │──│ Info_Personal  │  │ Cat_Roles│          │
│  │  (Acceso)    │  │  (Identidad)  │  │ (Permisos)│         │
│  └──────────────┘  └───────────────┘  └──────────┘          │
│                                                              │
│  Stored Procedures:                                          │
│  ├─ SP_RegistrarUsuarioNuevo      (Auto-registro)            │
│  ├─ SP_RegistrarUsuarioPorAdmin   (Alta administrativa)      │
│  ├─ SP_ConsultarPerfilPropio      (Mi perfil)                │
│  ├─ SP_ConsultarUsuarioPorAdmin   (Detalle para admin)       │
│  ├─ SP_EditarPerfilPropio         (Editar mi perfil)         │
│  ├─ SP_EditarUsuarioPorAdmin      (Admin edita usuario)      │
│  ├─ SP_ActualizarCredencialesPropio (Cambiar email/pass)     │
│  ├─ SP_CambiarEstatusUsuario      (Activar/Desactivar)      │
│  ├─ SP_EliminarUsuarioDefinitivamente (Hard delete)          │
│  ├─ SP_ListarInstructoresActivos  (Dropdown operativo)       │
│  └─ SP_ListarTodosInstructores_Historial (Filtro reportes)   │
│                                                              │
│  Vista: Vista_Usuarios (Grid del Admin)                      │
└─────────────────────────────────────────────────────────────┘
```

## Archivos incluidos

```
picade-laravel/
├── app/
│   ├── Models/
│   │   ├── User.php              ← Modelo principal (tabla Usuarios + wrappers de SPs)
│   │   ├── InfoPersonal.php      ← Modelo tabla Info_Personal
│   │   └── CatRol.php            ← Modelo tabla Cat_Roles
│   ├── Http/Controllers/
│   │   ├── Auth/
│   │   │   └── AuthController.php ← Login, Registro público, Logout
│   │   └── UserController.php     ← CRUD Admin + Perfil propio + APIs JSON
│   └── Providers/
│       └── AuthServiceProvider.php ← Gates de autorización (admin, coordinador, instructor)
├── config/
│   └── auth.php                   ← Fragmento de config (providers y guards)
├── database/migrations/
│   └── ...create_configuraciones_table.php  ← Tabla para config del login background
├── resources/views/auth/
│   ├── login.blade.php            ← Vista de login (réplica del diseño original)
│   └── register.blade.php         ← Vista de registro público
├── routes/
│   └── web.php                    ← Todas las rutas (auth + admin + perfil + api)
└── README.md                      ← Este archivo
```

## Instalación paso a paso

### 1. Copiar archivos

Copia cada archivo a la ruta correspondiente de tu proyecto Laravel:

```bash
# Modelos
cp app/Models/User.php        tu-proyecto/app/Models/
cp app/Models/InfoPersonal.php tu-proyecto/app/Models/
cp app/Models/CatRol.php      tu-proyecto/app/Models/

# Controllers
cp app/Http/Controllers/Auth/AuthController.php tu-proyecto/app/Http/Controllers/Auth/
cp app/Http/Controllers/UserController.php      tu-proyecto/app/Http/Controllers/

# Vistas
cp resources/views/auth/login.blade.php    tu-proyecto/resources/views/auth/
cp resources/views/auth/register.blade.php tu-proyecto/resources/views/auth/

# Rutas (integrar en tu web.php existente, no reemplazar)
# Revisar routes/web.php y copiar las rutas que necesites
```

### 2. Configurar auth.php

Edita `config/auth.php` de tu proyecto. Cambia las secciones indicadas en `config/auth.php` de este paquete:
- `defaults.passwords` → `'usuarios'`
- `guards.web.provider` → `'picade_users'`
- Agregar provider `'picade_users'` con `App\Models\User::class`

### 3. Configurar .env

```env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=PICADE
DB_USERNAME=tu_usuario
DB_PASSWORD=tu_password
DB_CHARSET=utf8mb4
DB_COLLATION=utf8mb4_spanish_ci
```

### 4. Ejecutar migración (tabla configuraciones)

```bash
php artisan migrate
```

### 5. Imagen de fondo del login

Coloca tu imagen default en:
```
public/images/picade-bg-default.jpg
```

Para cambiar dinámicamente desde admin, sube la imagen a `storage/app/public/` y actualiza:
```sql
UPDATE configuraciones SET valor = 'ruta/imagen.jpg' WHERE clave = 'login_bg_image';
```

### 6. Gates de autorización

Agrega el contenido de `AuthServiceProvider.php` al método `boot()` de tu provider existente.

### 7. Verificar que los SPs estén creados

Asegúrate de que los Stored Procedures estén ejecutados en la BD PICADE:
```bash
mysql -u root -p PICADE < archivo_de_stored_procedures.sql
```

## Flujo de autenticación

1. **Usuario visita** `/login` → ve el formulario con fondo configurable
2. **Escribe** su ficha O correo + contraseña
3. **AuthController** detecta si es email o ficha, busca en `Usuarios`, verifica `Activo`, valida hash Bcrypt
4. **Si es válido** → `Auth::login()` + redirección según rol
5. **Si falla** → mensaje específico (cuenta no existe, desactivada, contraseña incorrecta)

## Flujo de registro

1. **Usuario visita** `/register` → formulario de 8 campos
2. **Laravel valida** (primera capa: formato, longitud, edad)
3. **SP_RegistrarUsuarioNuevo** valida (segunda capa: duplicados, huella humana, concurrencia)
4. **Si éxito** → auto-login + redirect a dashboard
5. **Si error del SP** → se extrae el MESSAGE_TEXT y se muestra al usuario

## Mapeo Controller ↔ Stored Procedure

| Método del Controller              | Stored Procedure / Vista            | Ruta                        |
|------------------------------------|-------------------------------------|-----------------------------|
| `AuthController::login`            | Query directa a Usuarios            | `POST /login`               |
| `AuthController::register`         | `SP_RegistrarUsuarioNuevo`          | `POST /register`            |
| `UserController::index`            | `Vista_Usuarios`                    | `GET /admin/usuarios`       |
| `UserController::store`            | `SP_RegistrarUsuarioPorAdmin`       | `POST /admin/usuarios`      |
| `UserController::show`             | `SP_ConsultarUsuarioPorAdmin`       | `GET /admin/usuarios/{id}`  |
| `UserController::update`           | `SP_EditarUsuarioPorAdmin`          | `PUT /admin/usuarios/{id}`  |
| `UserController::toggleEstatus`    | `SP_CambiarEstatusUsuario`          | `PATCH /admin/usuarios/{id}/estatus` |
| `UserController::destroy`          | `SP_EliminarUsuarioDefinitivamente` | `DELETE /admin/usuarios/{id}` |
| `UserController::miPerfil`         | `SP_ConsultarPerfilPropio`          | `GET /perfil`               |
| `UserController::actualizarMiPerfil` | `SP_EditarPerfilPropio`           | `PUT /perfil`               |
| `UserController::actualizarMisCredenciales` | `SP_ActualizarCredencialesPropio` | `PUT /perfil/credenciales` |
| `UserController::apiInstructoresActivos` | `SP_ListarInstructoresActivos` | `GET /api/instructores/activos` |
| `UserController::apiInstructoresHistorial` | `SP_ListarTodosInstructores_Historial` | `GET /api/instructores/historial` |

## Notas técnicas

- **Hash de contraseñas**: Se usa `bcrypt()` de Laravel antes de pasar al SP. Los SPs reciben el hash ya generado.
- **Manejo de errores SP**: Los `SIGNAL SQLSTATE '45000'` se capturan como `QueryException` y se extraen con regex para mostrar al usuario.
- **Fondo configurable**: Se busca primero en tabla `configuraciones`, si no existe o es NULL, se usa `public/images/picade-bg-default.jpg`.
- **Rol por defecto**: `Fk_Rol = 4` (Participante) para auto-registro, alineado al DEFAULT del DDL.
