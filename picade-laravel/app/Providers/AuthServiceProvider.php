<?php

/**
 * ============================================================================
 * ARCHIVO: app/Providers/AuthServiceProvider.php
 * ============================================================================
 * Registra el Gate 'admin' para proteger las rutas de administración.
 *
 * IMPORTANTE: Agrega este código dentro del método boot() de tu
 * AuthServiceProvider existente.
 * ============================================================================
 */

namespace App\Providers;

use App\Models\User;
use Illuminate\Foundation\Support\Providers\AuthServiceProvider as ServiceProvider;
use Illuminate\Support\Facades\Gate;

class AuthServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // =====================================================================
        // GATE: 'admin'
        // Usado en las rutas: ->middleware('can:admin')
        //
        // Lógica: El usuario debe tener Fk_Rol = 1 (Administrador)
        // y estar Activo.
        // =====================================================================
        Gate::define('admin', function (User $user) {
            // Fk_Rol = 1 es el rol de Administrador según Cat_Roles
            return $user->Fk_Rol === 1 && $user->Activo;
        });

        // =====================================================================
        // GATE: 'coordinador'
        // Para rutas que requieran al menos nivel de Coordinador.
        // =====================================================================
        Gate::define('coordinador', function (User $user) {
            return in_array($user->Fk_Rol, [1, 2]) && $user->Activo;
        });

        // =====================================================================
        // GATE: 'instructor'
        // Para rutas que requieran al menos nivel de Instructor.
        // =====================================================================
        Gate::define('instructor', function (User $user) {
            return in_array($user->Fk_Rol, [1, 2, 3]) && $user->Activo;
        });
    }
}
