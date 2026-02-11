<?php

namespace App\Http\Controllers;

use App\Models\User;
use App\Models\CatRol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class UserController extends Controller
{
    // =========================================================================
    // LISTADO (Vista_Usuarios → Grid del Admin)
    // =========================================================================

    /**
     * Grid principal de usuarios.
     * GET /admin/usuarios
     *
     * Consume: Vista_Usuarios (VIEW en MySQL)
     */
    public function index()
    {
        $usuarios = User::listarParaGrid();
        $roles    = CatRol::where('Activo', 1)->get();

        return view('admin.usuarios.index', compact('usuarios', 'roles'));
    }

    // =========================================================================
    // CONSULTA DETALLADA (Para modal o formulario de edición)
    // =========================================================================

    /**
     * Detalle completo de un usuario (consumido por modal de edición vía AJAX).
     * GET /admin/usuarios/{id}
     *
     * Consume: SP_ConsultarUsuarioPorAdmin
     */
    public function show(int $id)
    {
        try {
            $perfil = User::consultarPorAdmin($id);

            if (!$perfil) {
                return response()->json([
                    'success' => false,
                    'mensaje' => 'Usuario no encontrado.',
                ], 404);
            }

            return response()->json([
                'success' => true,
                'data'    => $perfil,
            ]);
        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'success' => false,
                'mensaje' => $this->extraerMensajeSP($e),
            ], 422);
        }
    }

    // =========================================================================
    // ALTA ADMINISTRATIVA
    // =========================================================================

    /**
     * Formulario de creación (vista Blade).
     * GET /admin/usuarios/create
     */
    public function create()
    {
        $catalogos = $this->cargarCatalogos();

        return view('admin.usuarios.create', compact('catalogos'));
    }

    /**
     * Persistir nuevo usuario.
     * POST /admin/usuarios
     *
     * Consume: SP_RegistrarUsuarioPorAdmin
     */
    public function store(Request $request)
    {
        $request->validate($this->reglasValidacionAdmin());

        try {
            $idAdmin = Auth::id();

            // Manejo de foto de perfil
            $fotoUrl = null;
            if ($request->hasFile('foto_perfil')) {
                $fotoUrl = $request->file('foto_perfil')
                    ->store('fotos-perfil', 'public');
            }

            $resultado = User::registrarPorAdmin($idAdmin, [
                'ficha'              => $request->input('ficha'),
                'foto_url'           => $fotoUrl,
                'nombre'             => $request->input('nombre'),
                'apellido_paterno'   => $request->input('apellido_paterno'),
                'apellido_materno'   => $request->input('apellido_materno'),
                'fecha_nacimiento'   => $request->input('fecha_nacimiento'),
                'fecha_ingreso'      => $request->input('fecha_ingreso'),
                'email'              => $request->input('email'),
                'password'           => $request->input('password'),
                'id_rol'             => $request->input('id_rol'),
                'id_regimen'         => $request->input('id_regimen'),
                'id_puesto'          => $request->input('id_puesto'),
                'id_centro_trabajo'  => $request->input('id_centro_trabajo'),
                'id_departamento'    => $request->input('id_departamento'),
                'id_region'          => $request->input('id_region'),
                'id_gerencia'        => $request->input('id_gerencia'),
                'nivel'              => $request->input('nivel'),
                'clasificacion'      => $request->input('clasificacion'),
            ]);

            return redirect()
                ->route('admin.usuarios.index')
                ->with('success', $resultado->Mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            Log::warning('SP_RegistrarUsuarioPorAdmin falló', ['error' => $e->getMessage()]);

            return back()
                ->withInput()
                ->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    // =========================================================================
    // EDICIÓN POR ADMIN
    // =========================================================================

    /**
     * Formulario de edición (vista Blade).
     * GET /admin/usuarios/{id}/edit
     *
     * Consume: SP_ConsultarUsuarioPorAdmin (para pre-llenar el formulario)
     */
    public function edit(int $id)
    {
        try {
            $perfil    = User::consultarPorAdmin($id);
            $catalogos = $this->cargarCatalogos();

            return view('admin.usuarios.edit', compact('perfil', 'catalogos'));
        } catch (\Illuminate\Database\QueryException $e) {
            return redirect()
                ->route('admin.usuarios.index')
                ->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    /**
     * Persistir cambios del admin.
     * PUT /admin/usuarios/{id}
     *
     * Consume: SP_EditarUsuarioPorAdmin
     */
    public function update(Request $request, int $id)
    {
        $request->validate($this->reglasValidacionAdminEdicion($id));

        try {
            $idAdmin = Auth::id();

            // Manejo de foto
            $fotoUrl = $request->input('foto_url_actual');
            if ($request->hasFile('foto_perfil')) {
                // Borrar foto anterior si existe
                if ($fotoUrl && Storage::disk('public')->exists($fotoUrl)) {
                    Storage::disk('public')->delete($fotoUrl);
                }
                $fotoUrl = $request->file('foto_perfil')
                    ->store('fotos-perfil', 'public');
            }

            $resultado = User::editarPorAdmin($idAdmin, $id, [
                'ficha'              => $request->input('ficha'),
                'foto_url'           => $fotoUrl,
                'nombre'             => $request->input('nombre'),
                'apellido_paterno'   => $request->input('apellido_paterno'),
                'apellido_materno'   => $request->input('apellido_materno'),
                'fecha_nacimiento'   => $request->input('fecha_nacimiento'),
                'fecha_ingreso'      => $request->input('fecha_ingreso'),
                'email'              => $request->input('email'),
                'nueva_contrasena'   => $request->input('nueva_contrasena'),
                'id_rol'             => $request->input('id_rol'),
                'id_regimen'         => $request->input('id_regimen'),
                'id_puesto'          => $request->input('id_puesto', 0),
                'id_centro_trabajo'  => $request->input('id_centro_trabajo', 0),
                'id_departamento'    => $request->input('id_departamento', 0),
                'id_region'          => $request->input('id_region'),
                'id_gerencia'        => $request->input('id_gerencia', 0),
                'nivel'              => $request->input('nivel'),
                'clasificacion'      => $request->input('clasificacion'),
            ]);

            return redirect()
                ->route('admin.usuarios.index')
                ->with('success', $resultado->Mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            Log::warning('SP_EditarUsuarioPorAdmin falló', ['id' => $id, 'error' => $e->getMessage()]);

            return back()
                ->withInput()
                ->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    // =========================================================================
    // CAMBIO DE ESTATUS (Activar / Desactivar)
    // =========================================================================

    /**
     * Toggle de estatus (AJAX).
     * PATCH /admin/usuarios/{id}/estatus
     *
     * Consume: SP_CambiarEstatusUsuario
     */
    public function toggleEstatus(Request $request, int $id)
    {
        $request->validate([
            'nuevo_estatus' => 'required|in:0,1',
        ]);

        try {
            $resultado = User::cambiarEstatus(
                Auth::id(),
                $id,
                (int) $request->input('nuevo_estatus')
            );

            return response()->json([
                'success' => true,
                'mensaje' => $resultado->Mensaje,
                'accion'  => $resultado->Accion,
            ]);
        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'success' => false,
                'mensaje' => $this->extraerMensajeSP($e),
            ], 422);
        }
    }

    // =========================================================================
    // ELIMINACIÓN DEFINITIVA (Hard Delete)
    // =========================================================================

    /**
     * Eliminar usuario permanentemente (AJAX con confirmación).
     * DELETE /admin/usuarios/{id}
     *
     * Consume: SP_EliminarUsuarioDefinitivamente
     */
    public function destroy(int $id)
    {
        try {
            $resultado = User::eliminarDefinitivamente(Auth::id(), $id);

            return response()->json([
                'success' => true,
                'mensaje' => $resultado->Mensaje,
                'accion'  => $resultado->Accion,
            ]);
        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'success' => false,
                'mensaje' => $this->extraerMensajeSP($e),
            ], 422);
        }
    }

    // =========================================================================
    // PERFIL PROPIO (Para el usuario autenticado)
    // =========================================================================

    /**
     * Ver mi perfil.
     * GET /perfil
     *
     * Consume: SP_ConsultarPerfilPropio
     */
    public function miPerfil()
    {
        try {
            $perfil    = User::consultarPerfilPropio(Auth::id());
            $catalogos = $this->cargarCatalogos();

            return view('perfil.show', compact('perfil', 'catalogos'));
        } catch (\Illuminate\Database\QueryException $e) {
            return back()->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    /**
     * Actualizar mi perfil.
     * PUT /perfil
     *
     * Consume: SP_EditarPerfilPropio
     */
    public function actualizarMiPerfil(Request $request)
    {
        $request->validate([
            'ficha'            => 'required|string|max:50',
            'nombre'           => 'required|string|max:255',
            'apellido_paterno' => 'required|string|max:255',
            'apellido_materno' => 'required|string|max:255',
            'fecha_nacimiento' => 'required|date',
            'fecha_ingreso'    => 'required|date',
            'id_regimen'       => 'required|integer|min:1',
            'id_region'        => 'required|integer|min:1',
        ]);

        try {
            $fotoUrl = $request->input('foto_url_actual');
            if ($request->hasFile('foto_perfil')) {
                if ($fotoUrl && Storage::disk('public')->exists($fotoUrl)) {
                    Storage::disk('public')->delete($fotoUrl);
                }
                $fotoUrl = $request->file('foto_perfil')
                    ->store('fotos-perfil', 'public');
            }

            $resultado = User::editarPerfilPropio(Auth::id(), [
                'ficha'              => $request->input('ficha'),
                'foto_url'           => $fotoUrl,
                'nombre'             => $request->input('nombre'),
                'apellido_paterno'   => $request->input('apellido_paterno'),
                'apellido_materno'   => $request->input('apellido_materno'),
                'fecha_nacimiento'   => $request->input('fecha_nacimiento'),
                'fecha_ingreso'      => $request->input('fecha_ingreso'),
                'id_regimen'         => $request->input('id_regimen'),
                'id_puesto'          => $request->input('id_puesto', 0),
                'id_centro_trabajo'  => $request->input('id_centro_trabajo', 0),
                'id_departamento'    => $request->input('id_departamento', 0),
                'id_region'          => $request->input('id_region'),
                'id_gerencia'        => $request->input('id_gerencia', 0),
                'nivel'              => $request->input('nivel'),
                'clasificacion'      => $request->input('clasificacion'),
            ]);

            return back()->with('success', $resultado->Mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            return back()
                ->withInput()
                ->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    /**
     * Actualizar mis credenciales (email/password).
     * PUT /perfil/credenciales
     *
     * Consume: SP_ActualizarCredencialesPropio
     */
    public function actualizarMisCredenciales(Request $request)
    {
        $request->validate([
            'nuevo_email'    => 'nullable|email|max:255',
            'nueva_password' => 'nullable|string|min:8|confirmed',
        ]);

        try {
            $resultado = User::actualizarCredenciales(
                Auth::id(),
                $request->input('nuevo_email'),
                $request->input('nueva_password')
            );

            return back()->with('success', $resultado->Mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            return back()->withErrors(['sp_error' => $this->extraerMensajeSP($e)]);
        }
    }

    // =========================================================================
    // ENDPOINTS AJAX (Selectores / Dropdowns)
    // =========================================================================

    /**
     * Instructores activos (para dropdowns operativos).
     * GET /api/instructores/activos
     */
    public function apiInstructoresActivos()
    {
        return response()->json(User::listarInstructoresActivos());
    }

    /**
     * Todos los instructores (para filtros de reportes).
     * GET /api/instructores/historial
     */
    public function apiInstructoresHistorial()
    {
        return response()->json(User::listarInstructoresHistorial());
    }

    // =========================================================================
    // HELPERS PRIVADOS
    // =========================================================================

    /**
     * Carga todos los catálogos activos para los formularios de usuario.
     */
    private function cargarCatalogos(): array
    {
        return [
            'roles'            => DB::table('Cat_Roles')->where('Activo', 1)->get(),
            'regimenes'        => DB::table('Cat_Regimenes_Trabajo')->where('Activo', 1)->get(),
            'puestos'          => DB::table('Cat_Puestos_Trabajo')->where('Activo', 1)->get(),
            'centros_trabajo'  => DB::table('Cat_Centros_Trabajo')->where('Activo', 1)->get(),
            'departamentos'    => DB::table('Cat_Departamentos')->where('Activo', 1)->get(),
            'regiones'         => DB::table('Cat_Regiones_Trabajo')->where('Activo', 1)->get(),
            'gerencias'        => DB::table('Cat_Gerencias_Activos')->where('Activo', 1)->get(),
        ];
    }

    /**
     * Reglas de validación para alta administrativa.
     */
    private function reglasValidacionAdmin(): array
    {
        return [
            'ficha'              => 'required|string|max:50',
            'email'              => 'required|email|max:255',
            'password'           => 'required|string|min:8',
            'nombre'             => 'required|string|max:255',
            'apellido_paterno'   => 'required|string|max:255',
            'apellido_materno'   => 'required|string|max:255',
            'fecha_nacimiento'   => 'required|date',
            'fecha_ingreso'      => 'required|date',
            'id_rol'             => 'required|integer|min:1',
            'id_regimen'         => 'required|integer|min:1',
            'id_puesto'          => 'required|integer|min:1',
            'id_centro_trabajo'  => 'required|integer|min:1',
            'id_departamento'    => 'required|integer|min:1',
            'id_region'          => 'required|integer|min:1',
            'id_gerencia'        => 'required|integer|min:1',
            'foto_perfil'        => 'nullable|image|max:2048',
        ];
    }

    /**
     * Reglas para edición administrativa (password opcional).
     */
    private function reglasValidacionAdminEdicion(int $idUsuario): array
    {
        $reglas = $this->reglasValidacionAdmin();
        $reglas['password']          = 'nullable|string|min:8'; // No obligatorio en edición
        $reglas['nueva_contrasena']  = 'nullable|string|min:8'; // Campo de reset
        unset($reglas['password']);

        return $reglas;
    }

    /**
     * Extrae el MESSAGE_TEXT de un SIGNAL SQLSTATE '45000'.
     */
    private function extraerMensajeSP(\Illuminate\Database\QueryException $e): string
    {
        $mensaje = $e->getMessage();

        if (preg_match('/1644\s+(.+?)(?:\s*\(SQL:|$)/s', $mensaje, $matches)) {
            return trim(rtrim($matches[1], '")'));
        }

        return 'Ocurrió un error al procesar la solicitud. Intenta de nuevo.';
    }
}
