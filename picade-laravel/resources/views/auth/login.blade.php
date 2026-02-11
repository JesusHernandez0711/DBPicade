{{-- resources/views/auth/login.blade.php --}}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - Iniciar Sesión</title>

    {{-- Google Fonts --}}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700;800&display=swap" rel="stylesheet">

    <style>
        /* ============================================================
           RESET & BASE
           ============================================================ */
        *, *::before, *::after {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        html, body {
            height: 100%;
            font-family: 'Montserrat', sans-serif;
            overflow: hidden;
        }

        /* ============================================================
           FONDO CONFIGURABLE (la imagen viene del controller)
           ============================================================ */
        .login-wrapper {
            position: relative;
            width: 100%;
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .login-bg {
            position: absolute;
            inset: 0;
            background-image: url('{{ $bgImage }}');
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            z-index: 0;
        }

        /* Overlay oscuro sutil para legibilidad */
        .login-bg::after {
            content: '';
            position: absolute;
            inset: 0;
            background: linear-gradient(
                135deg,
                rgba(0, 0, 0, 0.15) 0%,
                rgba(0, 0, 0, 0.35) 100%
            );
        }

        /* ============================================================
           TARJETA DE LOGIN (Glassmorphism como en la captura)
           ============================================================ */
        .login-card {
            position: relative;
            z-index: 10;
            width: 100%;
            max-width: 420px;
            padding: 40px 36px 32px;
            background: rgba(255, 255, 255, 0.82);
            backdrop-filter: blur(18px) saturate(160%);
            -webkit-backdrop-filter: blur(18px) saturate(160%);
            border-radius: 16px;
            border: 1px solid rgba(255, 255, 255, 0.45);
            box-shadow:
                0 8px 32px rgba(0, 0, 0, 0.18),
                0 1px 4px rgba(0, 0, 0, 0.08);
            animation: cardEnter 0.6s cubic-bezier(0.22, 1, 0.36, 1) forwards;
            opacity: 0;
            transform: translateY(20px) scale(0.98);
        }

        @keyframes cardEnter {
            to {
                opacity: 1;
                transform: translateY(0) scale(1);
            }
        }

        /* ============================================================
           TÍTULO PICADE
           ============================================================ */
        .login-title {
            text-align: center;
            font-size: 2rem;
            font-weight: 800;
            letter-spacing: 3px;
            color: #1a3a5c;
            margin-bottom: 28px;
        }

        .login-title span {
            background: linear-gradient(135deg, #1a3a5c 0%, #2d6aa0 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }

        /* ============================================================
           CAMPOS DE FORMULARIO
           ============================================================ */
        .form-group {
            margin-bottom: 16px;
        }

        .form-input {
            width: 100%;
            padding: 13px 16px;
            font-family: 'Montserrat', sans-serif;
            font-size: 0.9rem;
            color: #333;
            background: rgba(255, 255, 255, 0.7);
            border: 1.5px solid #ccd5de;
            border-radius: 8px;
            outline: none;
            transition: all 0.25s ease;
        }

        .form-input::placeholder {
            color: #8a9ab0;
            font-weight: 400;
        }

        .form-input:focus {
            border-color: #2d6aa0;
            background: rgba(255, 255, 255, 0.95);
            box-shadow: 0 0 0 3px rgba(45, 106, 160, 0.12);
        }

        .form-input.is-invalid {
            border-color: #d9534f;
            box-shadow: 0 0 0 3px rgba(217, 83, 79, 0.1);
        }

        /* ============================================================
           CHECKBOX "RECORDAR" + LINK "¿OLVIDASTE?"
           ============================================================ */
        .form-options {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 20px;
            font-size: 0.82rem;
        }

        .remember-label {
            display: flex;
            align-items: center;
            gap: 6px;
            color: #555;
            cursor: pointer;
            user-select: none;
        }

        .remember-label input[type="checkbox"] {
            width: 16px;
            height: 16px;
            accent-color: #2d6aa0;
            cursor: pointer;
        }

        .forgot-link {
            color: #2d6aa0;
            text-decoration: none;
            font-weight: 600;
            transition: color 0.2s;
        }

        .forgot-link:hover {
            color: #1a3a5c;
            text-decoration: underline;
        }

        /* ============================================================
           BOTONES (REGISTRARSE verde, INICIAR SESIÓN azul)
           Exactamente como en la captura de pantalla
           ============================================================ */
        .btn-row {
            display: flex;
            gap: 12px;
            margin-top: 4px;
        }

        .btn {
            flex: 1;
            padding: 12px 16px;
            font-family: 'Montserrat', sans-serif;
            font-size: 0.82rem;
            font-weight: 700;
            letter-spacing: 1px;
            text-transform: uppercase;
            color: #fff;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            text-align: center;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            transition: all 0.25s ease;
        }

        .btn-register {
            background: linear-gradient(135deg, #43a047, #2e7d32);
        }

        .btn-register:hover {
            background: linear-gradient(135deg, #388e3c, #1b5e20);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(46, 125, 50, 0.35);
        }

        .btn-login {
            background: linear-gradient(135deg, #1976d2, #1565c0);
        }

        .btn-login:hover {
            background: linear-gradient(135deg, #1565c0, #0d47a1);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(25, 118, 210, 0.35);
        }

        .btn:active {
            transform: translateY(0);
        }

        /* ============================================================
           ERRORES
           ============================================================ */
        .error-text {
            display: block;
            color: #d9534f;
            font-size: 0.78rem;
            margin-top: 5px;
            font-weight: 500;
        }

        .alert-error {
            background: rgba(217, 83, 79, 0.08);
            border: 1px solid rgba(217, 83, 79, 0.25);
            border-radius: 8px;
            padding: 10px 14px;
            margin-bottom: 16px;
            font-size: 0.82rem;
            color: #a94442;
        }

        .alert-success {
            background: rgba(76, 175, 80, 0.08);
            border: 1px solid rgba(76, 175, 80, 0.25);
            border-radius: 8px;
            padding: 10px 14px;
            margin-bottom: 16px;
            font-size: 0.82rem;
            color: #2e7d32;
        }

        /* ============================================================
           RESPONSIVE
           ============================================================ */
        @media (max-width: 480px) {
            .login-card {
                margin: 16px;
                padding: 28px 24px 24px;
            }

            .btn-row {
                flex-direction: column;
            }

            .login-title {
                font-size: 1.6rem;
            }
        }

        /* ============================================================
           LOADING SPINNER (para submit)
           ============================================================ */
        .btn .spinner {
            display: none;
            width: 18px;
            height: 18px;
            border: 2px solid rgba(255,255,255,0.4);
            border-top-color: #fff;
            border-radius: 50%;
            animation: spin 0.6s linear infinite;
            margin-right: 8px;
        }

        .btn.loading .spinner {
            display: inline-block;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>

<div class="login-wrapper">
    {{-- Fondo configurable --}}
    <div class="login-bg"></div>

    {{-- Tarjeta de Login --}}
    <div class="login-card">
        <h1 class="login-title"><span>PICADE</span></h1>

        {{-- Mensajes flash --}}
        @if(session('success'))
            <div class="alert-success">{{ session('success') }}</div>
        @endif

        @if($errors->has('credencial') || $errors->has('password'))
            <div class="alert-error">
                {{ $errors->first('credencial') ?: $errors->first('password') }}
            </div>
        @endif

        {{-- Formulario --}}
        <form method="POST" action="{{ route('login.post') }}" id="loginForm">
            @csrf

            {{-- Campo: Correo electrónico o Ficha --}}
            <div class="form-group">
                <input
                    type="text"
                    name="credencial"
                    class="form-input @error('credencial') is-invalid @enderror"
                    placeholder="Correo electrónico o ficha de usuario"
                    value="{{ old('credencial') }}"
                    autocomplete="username"
                    autofocus
                    required
                >
            </div>

            {{-- Campo: Contraseña --}}
            <div class="form-group">
                <input
                    type="password"
                    name="password"
                    class="form-input @error('password') is-invalid @enderror"
                    placeholder="Contraseña"
                    autocomplete="current-password"
                    required
                >
            </div>

            {{-- Opciones: Recordar + ¿Olvidaste? --}}
            <div class="form-options">
                <label class="remember-label">
                    <input
                        type="checkbox"
                        name="recordar"
                        {{ old('recordar') ? 'checked' : '' }}
                    >
                    Recordar
                </label>
                <a href="{{ route('password.request') }}" class="forgot-link">
                    ¿Olvidaste tu contraseña?
                </a>
            </div>

            {{-- Botones --}}
            <div class="btn-row">
                <a href="{{ route('register') }}" class="btn btn-register">
                    REGISTRARSE
                </a>
                <button type="submit" class="btn btn-login" id="btnLogin">
                    <span class="spinner"></span>
                    INICIAR SESIÓN
                </button>
            </div>
        </form>
    </div>
</div>

<script>
    // Spinner al enviar el formulario
    document.getElementById('loginForm').addEventListener('submit', function() {
        const btn = document.getElementById('btnLogin');
        btn.classList.add('loading');
        btn.disabled = true;
    });
</script>

</body>
</html>
