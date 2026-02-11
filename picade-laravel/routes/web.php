<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\UserController;

/*
|--------------------------------------------------------------------------
| PICADE - Rutas de Autenticación (Públicas)
|--------------------------------------------------------------------------
| Estas rutas son accesibles sin autenticación.
*/

// =========================================================================
// LOGIN
// =========================================================================
Route::get('/login', [AuthController::class, 'showLogin'])
    ->name('login')
    ->middleware('guest');

Route::post('/login', [AuthController::class, 'login'])
    ->name('login.post')
    ->middleware('guest');

// =========================================================================
// REGISTRO (Auto-registro público → SP_RegistrarUsuarioNuevo)
// =========================================================================
Route::get('/register', [AuthController::class, 'showRegister'])
    ->name('register')
    ->middleware('guest');

Route::post('/register', [AuthController::class, 'register'])
    ->name('register.post')
    ->middleware('guest');

// =========================================================================
// LOGOUT
// =========================================================================
Route::post('/logout', [AuthController::class, 'logout'])
    ->name('logout')
    ->middleware('auth');

// =========================================================================
// RECUPERAR CONTRASEÑA (placeholder — implementar según necesidad)
// =========================================================================
Route::get('/password/reset', function () {
    return view('auth.forgot-password');
})->name('password.request')->middleware('guest');


/*
|--------------------------------------------------------------------------
| PICADE - Rutas Protegidas (Requieren Autenticación)
|--------------------------------------------------------------------------
*/
Route::middleware('auth')->group(function () {

    // =====================================================================
    // DASHBOARD GENÉRICO (Participantes y cualquier rol)
    // =====================================================================
    Route::get('/', function () {
        return redirect()->route('dashboard');
    });

    Route::get('/dashboard', function () {
        return view('dashboard');
    })->name('dashboard');

    // =====================================================================
    // MI PERFIL (SP_ConsultarPerfilPropio / SP_EditarPerfilPropio)
    // =====================================================================
    Route::get('/perfil', [UserController::class, 'miPerfil'])
        ->name('perfil.show');

    Route::put('/perfil', [UserController::class, 'actualizarMiPerfil'])
        ->name('perfil.update');

    Route::put('/perfil/credenciales', [UserController::class, 'actualizarMisCredenciales'])
        ->name('perfil.credenciales');

    // =====================================================================
    // ADMINISTRACIÓN DE USUARIOS (Solo Admin)
    // =====================================================================
    Route::prefix('admin')->name('admin.')->middleware('can:admin')->group(function () {

        // Dashboard del Admin
        Route::get('/dashboard', function () {
            return view('admin.dashboard');
        })->name('dashboard');

        // CRUD de Usuarios
        Route::prefix('usuarios')->name('usuarios.')->group(function () {

            // Listado (Vista_Usuarios)
            Route::get('/', [UserController::class, 'index'])
                ->name('index');

            // Crear (SP_RegistrarUsuarioPorAdmin)
            Route::get('/create', [UserController::class, 'create'])
                ->name('create');
            Route::post('/', [UserController::class, 'store'])
                ->name('store');

            // Detalle JSON (SP_ConsultarUsuarioPorAdmin) — para modales AJAX
            Route::get('/{id}', [UserController::class, 'show'])
                ->name('show')
                ->where('id', '[0-9]+');

            // Editar (SP_EditarUsuarioPorAdmin)
            Route::get('/{id}/edit', [UserController::class, 'edit'])
                ->name('edit')
                ->where('id', '[0-9]+');
            Route::put('/{id}', [UserController::class, 'update'])
                ->name('update')
                ->where('id', '[0-9]+');

            // Toggle Estatus (SP_CambiarEstatusUsuario) — AJAX
            Route::patch('/{id}/estatus', [UserController::class, 'toggleEstatus'])
                ->name('estatus')
                ->where('id', '[0-9]+');

            // Eliminar Definitivamente (SP_EliminarUsuarioDefinitivamente) — AJAX
            Route::delete('/{id}', [UserController::class, 'destroy'])
                ->name('destroy')
                ->where('id', '[0-9]+');
        });
    });

    // =====================================================================
    // API INTERNA (JSON — para selectores Vue.js)
    // =====================================================================
    Route::prefix('api')->group(function () {

        // Instructores activos (SP_ListarInstructoresActivos)
        Route::get('/instructores/activos', [UserController::class, 'apiInstructoresActivos']);

        // Instructores historial (SP_ListarTodosInstructores_Historial)
        Route::get('/instructores/historial', [UserController::class, 'apiInstructoresHistorial']);
    });
});
