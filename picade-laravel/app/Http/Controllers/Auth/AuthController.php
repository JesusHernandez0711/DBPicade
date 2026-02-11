<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;

class AuthController extends Controller
{
    // =========================================================================
    // VISTAS
    // =========================================================================

    /**
     * Muestra el formulario de Login
     * GET /login
     */
    public function showLogin()
    {
        // Obtener imagen de fondo configurable (si existe la tabla de configuración)
        $bgImage = $this->obtenerFondoLogin();

        return view('auth.login', compact('bgImage'));
    }

    /**
     * Muestra el formulario de Registro público
     * GET /register
     */
    public function showRegister()
    {
        $bgImage = $this->obtenerFondoLogin();

        return view('auth.register', compact('bgImage'));
    }

    // =========================================================================
    // ACCIONES DE AUTENTICACIÓN
    // =========================================================================

    /**
     * Procesa el Login
     * POST /login
     *
     * Soporta login por Ficha O por Email (según lo que escriba el usuario).
     * Valida que el usuario esté Activo antes de permitir el acceso.
     */
    public function login(Request $request)
    {
        $request->validate([
            'credencial'  => 'required|string|max:255',
            'password'    => 'required|string',
        ], [
            'credencial.required' => 'Ingresa tu correo electrónico o ficha de usuario.',
            'password.required'   => 'Ingresa tu contraseña.',
        ]);

        $credencial = trim($request->input('credencial'));
        $password   = $request->input('password');
        $recordar   = $request->boolean('recordar');

        // ---------------------------------------------------------------
        // PASO 1: Determinar si es Email o Ficha
        // ---------------------------------------------------------------
        $campo = filter_var($credencial, FILTER_VALIDATE_EMAIL) ? 'Email' : 'Ficha';

        // ---------------------------------------------------------------
        // PASO 2: Buscar al usuario en la BD
        // ---------------------------------------------------------------
        $usuario = User::where($campo, $credencial)->first();

        if (!$usuario) {
            return back()
                ->withInput($request->only('credencial', 'recordar'))
                ->withErrors(['credencial' => 'No se encontró una cuenta con esa ' . ($campo === 'Email' ? 'dirección de correo' : 'ficha') . '.']);
        }

        // ---------------------------------------------------------------
        // PASO 3: Verificar que esté Activo
        // ---------------------------------------------------------------
        if (!$usuario->Activo) {
            return back()
                ->withInput($request->only('credencial', 'recordar'))
                ->withErrors(['credencial' => 'Tu cuenta está desactivada. Contacta al Administrador del sistema.']);
        }

        // ---------------------------------------------------------------
        // PASO 4: Verificar Contraseña (Bcrypt)
        // ---------------------------------------------------------------
        if (!Hash::check($password, $usuario->Contraseña)) {
            return back()
                ->withInput($request->only('credencial', 'recordar'))
                ->withErrors(['password' => 'Contraseña incorrecta.']);
        }

        // ---------------------------------------------------------------
        // PASO 5: Autenticar con Laravel (Session)
        // ---------------------------------------------------------------
        Auth::login($usuario, $recordar);

        $request->session()->regenerate();

        // Redirigir según rol
        return $this->redirigirPorRol($usuario);
    }

    /**
     * Procesa el Registro público (Self-Service)
     * POST /register
     *
     * Invoca SP_RegistrarUsuarioNuevo que maneja todas las validaciones
     * de duplicados, huella humana, paradoja temporal, etc.
     */
    public function register(Request $request)
    {
        // ---------------------------------------------------------------
        // PASO 1: Validación en Laravel (primera capa, antes del SP)
        // ---------------------------------------------------------------
        $request->validate([
            'ficha'             => 'required|string|max:50',
            'email'             => 'required|email|max:255',
            'password'          => 'required|string|min:8|confirmed',
            'nombre'            => 'required|string|max:255',
            'apellido_paterno'  => 'required|string|max:255',
            'apellido_materno'  => 'required|string|max:255',
            'fecha_nacimiento'  => 'required|date|before:-18 years',
            'fecha_ingreso'     => 'required|date|after_or_equal:fecha_nacimiento',
        ], [
            'ficha.required'            => 'La ficha de usuario es obligatoria.',
            'email.required'            => 'El correo electrónico es obligatorio.',
            'email.email'               => 'Ingresa un correo electrónico válido.',
            'password.required'         => 'La contraseña es obligatoria.',
            'password.min'              => 'La contraseña debe tener al menos 8 caracteres.',
            'password.confirmed'        => 'Las contraseñas no coinciden.',
            'nombre.required'           => 'El nombre es obligatorio.',
            'apellido_paterno.required' => 'El apellido paterno es obligatorio.',
            'apellido_materno.required' => 'El apellido materno es obligatorio.',
            'fecha_nacimiento.required' => 'La fecha de nacimiento es obligatoria.',
            'fecha_nacimiento.before'   => 'Debes ser mayor de 18 años.',
            'fecha_ingreso.required'    => 'La fecha de ingreso es obligatoria.',
            'fecha_ingreso.after_or_equal' => 'La fecha de ingreso no puede ser anterior a la fecha de nacimiento.',
        ]);

        // ---------------------------------------------------------------
        // PASO 2: Invocar el Stored Procedure (segunda capa de validación)
        // ---------------------------------------------------------------
        try {
            $resultado = User::registrarNuevo([
                'ficha'             => $request->input('ficha'),
                'email'             => $request->input('email'),
                'password'          => $request->input('password'),
                'nombre'            => $request->input('nombre'),
                'apellido_paterno'  => $request->input('apellido_paterno'),
                'apellido_materno'  => $request->input('apellido_materno'),
                'fecha_nacimiento'  => $request->input('fecha_nacimiento'),
                'fecha_ingreso'     => $request->input('fecha_ingreso'),
            ]);

            // ---------------------------------------------------------------
            // PASO 3: Auto-login tras registro exitoso
            // ---------------------------------------------------------------
            $nuevoUsuario = User::find($resultado->Id_Usuario);

            if ($nuevoUsuario) {
                Auth::login($nuevoUsuario);
                $request->session()->regenerate();
            }

            return redirect()
                ->route('dashboard')
                ->with('success', $resultado->Mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            // Los SPs lanzan SIGNAL SQLSTATE '45000' con MESSAGE_TEXT
            // Laravel los captura como QueryException con código HY000 / 45000
            $mensajeSP = $this->extraerMensajeSP($e);

            Log::warning('SP_RegistrarUsuarioNuevo rechazó registro', [
                'ficha'   => $request->input('ficha'),
                'email'   => $request->input('email'),
                'error'   => $mensajeSP,
            ]);

            return back()
                ->withInput($request->except('password', 'password_confirmation'))
                ->withErrors(['registro' => $mensajeSP]);
        }
    }

    /**
     * Cierra la sesión del usuario
     * POST /logout
     */
    public function logout(Request $request)
    {
        Auth::logout();

        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login');
    }

    // =========================================================================
    // MÉTODOS PRIVADOS (HELPERS)
    // =========================================================================

    /**
     * Redirige al dashboard según el rol del usuario.
     */
    private function redirigirPorRol(User $usuario): \Illuminate\Http\RedirectResponse
    {
        // Cargar el código del rol para decidir la ruta
        $usuario->load('rol');

        $rutaDestino = match ($usuario->rol?->Codigo) {
            'Admin'       => 'admin.dashboard',
            'Coordinador' => 'coordinador.dashboard',
            'Instructor'  => 'instructor.dashboard',
            default       => 'dashboard', // Participante u otro
        };

        // Si la ruta nombrada no existe, ir al dashboard genérico
        if (!route($rutaDestino, [], false)) {
            $rutaDestino = 'dashboard';
        }

        return redirect()->intended(route($rutaDestino));
    }

    /**
     * Extrae el MESSAGE_TEXT de un SIGNAL SQLSTATE '45000' capturado como QueryException.
     *
     * Los SPs de PICADE usan el formato:
     *   SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO [409]: ...'
     *
     * Laravel envuelve esto en un PDOException -> QueryException con el formato:
     *   "SQLSTATE[45000]: <<1>> General error: 1644 CONFLICTO [409]: ..."
     */
    private function extraerMensajeSP(\Illuminate\Database\QueryException $e): string
    {
        $mensaje = $e->getMessage();

        // Buscar el patrón del MESSAGE_TEXT dentro del error
        if (preg_match('/1644\s+(.+)$/s', $mensaje, $matches)) {
            // Limpiar posibles comillas y paréntesis residuales
            return trim(rtrim($matches[1], '")'));
        }

        // Si no lo encontramos, devolver un mensaje genérico
        return 'Ocurrió un error al procesar tu solicitud. Intenta de nuevo.';
    }

    /**
     * Obtiene la URL de la imagen de fondo para el login.
     * Configurable desde el panel de administración.
     *
     * NOTA: Debes crear una tabla 'configuraciones' o usar un archivo .env.
     * Aquí se muestra la versión con tabla, si prefieres .env puedes usar config().
     */
    private function obtenerFondoLogin(): string
    {
        // Opción 1: Desde tabla de configuraciones (recomendado para "configurable desde admin")
        try {
            $config = DB::table('configuraciones')
                ->where('clave', 'login_bg_image')
                ->value('valor');

            if ($config) {
                return asset('storage/' . $config);
            }
        } catch (\Exception $e) {
            // La tabla no existe aún, usar default
        }

        // Opción 2: Default desde public/images
        return asset('images/picade-bg-default.jpg');
    }
}
