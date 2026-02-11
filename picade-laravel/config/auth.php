<?php

/**
 * ============================================================================
 * ARCHIVO: config/auth.php (FRAGMENTO — SOLO LAS SECCIONES A MODIFICAR)
 * ============================================================================
 *
 * Modifica tu config/auth.php existente con estos cambios para que Laravel
 * reconozca la tabla 'Usuarios' y la columna 'Contraseña' de PICADE.
 *
 * NO reemplaces todo el archivo, solo actualiza las secciones indicadas.
 * ============================================================================
 */

return [

    // ... (mantener lo demás igual)

    /*
    |--------------------------------------------------------------------------
    | Authentication Guards
    |--------------------------------------------------------------------------
    | Mantener 'web' como default, pero apuntar al provider 'picade_users'.
    */
    'defaults' => [
        'guard' => 'web',
        'passwords' => 'usuarios',
    ],

    'guards' => [
        'web' => [
            'driver' => 'session',
            'provider' => 'picade_users', // <-- CAMBIADO
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | User Providers
    |--------------------------------------------------------------------------
    | Crear un provider que apunte al modelo User de PICADE.
    */
    'providers' => [
        'picade_users' => [
            'driver' => 'eloquent',
            'model'  => App\Models\User::class, // Tu modelo con tabla 'Usuarios'
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Resetting Passwords
    |--------------------------------------------------------------------------
    | Configuración para reset de passwords usando la tabla Usuarios.
    */
    'passwords' => [
        'usuarios' => [
            'provider' => 'picade_users',
            'table'    => 'password_reset_tokens',
            'expire'   => 60,
            'throttle' => 60,
        ],
    ],

];
