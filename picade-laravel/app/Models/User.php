<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Support\Facades\DB;

class User extends Authenticatable
{
    use Notifiable;

    // =========================================================================
    // CONFIGURACIÓN DE TABLA (Alineada al DDL de PICADE)
    // =========================================================================
    protected $table      = 'Usuarios';
    protected $primaryKey = 'Id_Usuario';
    protected $connection = 'mysql'; // Ajustar si usas otra conexión

    // Laravel busca 'password' por defecto; le decimos que use 'Contraseña'
    public function getAuthPasswordName(): string
    {
        return 'Contraseña';
    }

    // Deshabilitamos timestamps automáticos de Laravel porque
    // los SPs ya manejan created_at y updated_at
    public $timestamps = false;

    protected $fillable = [
        'Ficha',
        'Email',
        'Contraseña',
        'Foto_Perfil_Url',
        'Fk_Id_InfoPersonal',
        'Fk_Rol',
        'Activo',
        'Fk_Usuario_Created_By',
        'Fk_Usuario_Updated_By',
    ];

    protected $hidden = [
        'Contraseña',
    ];

    protected $casts = [
        'Activo'     => 'boolean',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    // =========================================================================
    // RELACIONES ELOQUENT
    // =========================================================================

    /**
     * Relación 1:1 con Info_Personal
     */
    public function infoPersonal()
    {
        return $this->belongsTo(InfoPersonal::class, 'Fk_Id_InfoPersonal', 'Id_InfoPersonal');
    }

    /**
     * Relación con Cat_Roles
     */
    public function rol()
    {
        return $this->belongsTo(CatRol::class, 'Fk_Rol', 'Id_Rol');
    }

    /**
     * Quien creó este usuario
     */
    public function creadoPor()
    {
        return $this->belongsTo(User::class, 'Fk_Usuario_Created_By', 'Id_Usuario');
    }

    /**
     * Quien actualizó este usuario
     */
    public function actualizadoPor()
    {
        return $this->belongsTo(User::class, 'Fk_Usuario_Updated_By', 'Id_Usuario');
    }

    // =========================================================================
    // ACCESSORS (Helpers para las vistas)
    // =========================================================================

    /**
     * Nombre completo concatenado desde la relación Info_Personal
     */
    public function getNombreCompletoAttribute(): string
    {
        if ($this->infoPersonal) {
            return trim(
                $this->infoPersonal->Nombre . ' ' .
                $this->infoPersonal->Apellido_Paterno . ' ' .
                $this->infoPersonal->Apellido_Materno
            );
        }
        return '';
    }

    /**
     * Código del rol (para middleware y guards)
     */
    public function getCodigoRolAttribute(): ?string
    {
        return $this->rol?->Codigo;
    }

    // =========================================================================
    // MÉTODOS ESTÁTICOS: Wrappers de Stored Procedures
    // =========================================================================

    /**
     * Llama a SP_RegistrarUsuarioNuevo (Auto-registro público)
     *
     * @param array $datos  Datos del formulario de registro
     * @return object       Resultado del SP {Mensaje, Id_Usuario, Accion}
     * @throws \Exception   Si el SP retorna un error SQLSTATE 45000
     */
    public static function registrarNuevo(array $datos): object
    {
        $resultado = DB::select('CALL SP_RegistrarUsuarioNuevo(?, ?, ?, ?, ?, ?, ?, ?)', [
            $datos['ficha'],
            $datos['email'],
            bcrypt($datos['password']),       // Hash Bcrypt antes de enviarlo al SP
            $datos['nombre'],
            $datos['apellido_paterno'],
            $datos['apellido_materno'],
            $datos['fecha_nacimiento'],
            $datos['fecha_ingreso'],
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_RegistrarUsuarioPorAdmin (Alta administrativa)
     */
    public static function registrarPorAdmin(int $idAdmin, array $datos): object
    {
        $resultado = DB::select('CALL SP_RegistrarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
            $idAdmin,
            $datos['ficha'],
            $datos['foto_url'] ?? null,
            $datos['nombre'],
            $datos['apellido_paterno'],
            $datos['apellido_materno'],
            $datos['fecha_nacimiento'],
            $datos['fecha_ingreso'],
            $datos['email'],
            bcrypt($datos['password']),
            $datos['id_rol'],
            $datos['id_regimen'],
            $datos['id_puesto'],
            $datos['id_centro_trabajo'],
            $datos['id_departamento'],
            $datos['id_region'],
            $datos['id_gerencia'],
            $datos['nivel'] ?? null,
            $datos['clasificacion'] ?? null,
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_ConsultarPerfilPropio
     */
    public static function consultarPerfilPropio(int $idUsuario): ?object
    {
        $resultado = DB::select('CALL SP_ConsultarPerfilPropio(?)', [$idUsuario]);
        return $resultado[0] ?? null;
    }

    /**
     * Llama a SP_ConsultarUsuarioPorAdmin
     */
    public static function consultarPorAdmin(int $idUsuarioObjetivo): ?object
    {
        $resultado = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$idUsuarioObjetivo]);
        return $resultado[0] ?? null;
    }

    /**
     * Llama a SP_EditarPerfilPropio
     */
    public static function editarPerfilPropio(int $idSesion, array $datos): object
    {
        $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
            $idSesion,
            $datos['ficha'],
            $datos['foto_url'] ?? null,
            $datos['nombre'],
            $datos['apellido_paterno'],
            $datos['apellido_materno'],
            $datos['fecha_nacimiento'],
            $datos['fecha_ingreso'],
            $datos['id_regimen'],
            $datos['id_puesto'] ?? 0,
            $datos['id_centro_trabajo'] ?? 0,
            $datos['id_departamento'] ?? 0,
            $datos['id_region'],
            $datos['id_gerencia'] ?? 0,
            $datos['nivel'] ?? null,
            $datos['clasificacion'] ?? null,
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_EditarUsuarioPorAdmin
     */
    public static function editarPorAdmin(int $idAdmin, int $idObjetivo, array $datos): object
    {
        $resultado = DB::select('CALL SP_EditarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
            $idAdmin,
            $idObjetivo,
            $datos['ficha'],
            $datos['foto_url'] ?? null,
            $datos['nombre'],
            $datos['apellido_paterno'],
            $datos['apellido_materno'],
            $datos['fecha_nacimiento'],
            $datos['fecha_ingreso'],
            $datos['email'],
            $datos['nueva_contrasena'] ?? null,
            $datos['id_rol'],
            $datos['id_regimen'],
            $datos['id_puesto'] ?? 0,
            $datos['id_centro_trabajo'] ?? 0,
            $datos['id_departamento'] ?? 0,
            $datos['id_region'] ?? 0,
            $datos['id_gerencia'] ?? 0,
            $datos['nivel'] ?? null,
            $datos['clasificacion'] ?? null,
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_CambiarEstatusUsuario
     */
    public static function cambiarEstatus(int $idAdmin, int $idObjetivo, int $nuevoEstatus): object
    {
        $resultado = DB::select('CALL SP_CambiarEstatusUsuario(?, ?, ?)', [
            $idAdmin,
            $idObjetivo,
            $nuevoEstatus,
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_EliminarUsuarioDefinitivamente
     */
    public static function eliminarDefinitivamente(int $idAdmin, int $idObjetivo): object
    {
        $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
            $idAdmin,
            $idObjetivo,
        ]);

        return $resultado[0];
    }

    /**
     * Llama a SP_ActualizarCredencialesPropio
     */
    public static function actualizarCredenciales(int $idSesion, ?string $nuevoEmail, ?string $nuevaContrasena): object
    {
        $hashPass = $nuevaContrasena ? bcrypt($nuevaContrasena) : null;

        $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
            $idSesion,
            $nuevoEmail,
            $hashPass,
        ]);

        return $resultado[0];
    }

    // =========================================================================
    // MÉTODOS ESTÁTICOS: Listados (Selectores/Dropdowns)
    // =========================================================================

    /**
     * Llama a SP_ListarInstructoresActivos (Para dropdowns operativos)
     */
    public static function listarInstructoresActivos(): array
    {
        return DB::select('CALL SP_ListarInstructoresActivos()');
    }

    /**
     * Llama a SP_ListarTodosInstructores_Historial (Para filtros de reportes)
     */
    public static function listarInstructoresHistorial(): array
    {
        return DB::select('CALL SP_ListarTodosInstructores_Historial()');
    }

    /**
     * Consulta la Vista_Usuarios para el Grid del Admin
     */
    public static function listarParaGrid()
    {
        return DB::table('Vista_Usuarios')->get();
    }
}
