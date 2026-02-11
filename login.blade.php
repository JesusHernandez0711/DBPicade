{{-- resources/views/auth/login.blade.php --}}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - Iniciar Sesión</title>
    <link rel="shortcut icon" href="">

    <!-- CSS de Bootstrap desde CDN -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons/font/bootstrap-icons.css">

    <!-- Google Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700;800&display=swap" rel="stylesheet">

    <style>
        /* =====================================================
           Solo estilos que Bootstrap NO cubre:
           fondo dinámico, glassmorphism y gradientes de botón
           ===================================================== */
        body {
            font-family: 'Montserrat', sans-serif;
            height: 100vh;
            overflow: hidden;
            margin: 0;
        }

        .login-bg {
            position: fixed;
            inset: 0;
            background-image: url('{{ $bgImage }}');
            background-size: cover;
            background-position: center;
            z-index: 0;
        }

        .login-bg::after {
            content: '';
            position: absolute;
            inset: 0;
            background: linear-gradient(135deg, rgba(0,0,0,0.15), rgba(0,0,0,0.35));
        }

        .glass-card {
            background: rgba(255, 255, 255, 0.82);
            backdrop-filter: blur(18px) saturate(160%);
            -webkit-backdrop-filter: blur(18px) saturate(160%);
            border: 1px solid rgba(255, 255, 255, 0.45);
            animation: cardEnter 0.6s cubic-bezier(0.22, 1, 0.36, 1) forwards;
            opacity: 0;
            transform: translateY(20px) scale(0.98);
        }

        @keyframes cardEnter {
            to { opacity: 1; transform: translateY(0) scale(1); }
        }

        .login-title {
            background: linear-gradient(135deg, #1a3a5c, #2d6aa0);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            letter-spacing: 3px;
        }

        .form-control:focus {
            border-color: #2d6aa0;
            box-shadow: 0 0 0 0.2rem rgba(45, 106, 160, 0.15);
        }

        .btn-picade-green {
            background: linear-gradient(135deg, #43a047, #2e7d32);
            border: none; color: #fff;
        }
        .btn-picade-green:hover {
            background: linear-gradient(135deg, #388e3c, #1b5e20);
            color: #fff; transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(46,125,50,0.35);
        }

        .btn-picade-blue {
            background: linear-gradient(135deg, #1976d2, #1565c0);
            border: none; color: #fff;
        }
        .btn-picade-blue:hover {
            background: linear-gradient(135deg, #1565c0, #0d47a1);
            color: #fff; transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(25,118,210,0.35);
        }

        .forgot-link { color: #2d6aa0; font-weight: 600; }
        .forgot-link:hover { color: #1a3a5c; }

        .spinner-btn {
            display: none; width: 18px; height: 18px;
            border: 2px solid rgba(255,255,255,0.4);
            border-top-color: #fff; border-radius: 50%;
            animation: spin 0.6s linear infinite;
        }
        .loading .spinner-btn { display: inline-block; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>

    <!-- Fondo configurable desde admin -->
    <div class="login-bg"></div>

    <!-- ===================================================================
         LAYOUT RESPONSIVO CON BOOTSTRAP 5
         col-11      → móvil (margen lateral mínimo)
         col-sm-8    → ≥576px tablets pequeñas
         col-md-6    → ≥768px tablets
         col-lg-5    → ≥992px laptops
         col-xl-4    → ≥1200px escritorio
         =================================================================== -->
    <div class="d-flex align-items-center justify-content-center position-relative" style="min-height:100vh; z-index:10;">
        <div class="container">
            <div class="row justify-content-center">
                <div class="col-11 col-sm-8 col-md-6 col-lg-5 col-xl-4">
                    <div class="glass-card rounded-4 shadow-lg p-4 p-md-5">

                        <!-- Título -->
                        <h1 class="login-title text-center fw-bold fs-2 mb-4">PICADE</h1>

                        <!-- Alertas -->
                        @if(session('success'))
                            <div class="alert alert-success alert-dismissible fade show py-2 small" role="alert">
                                {{ session('success') }}
                                <button type="button" class="btn-close btn-sm" data-bs-dismiss="alert"></button>
                            </div>
                        @endif

                        @if($errors->has('credencial') || $errors->has('password'))
                            <div class="alert alert-danger py-2 small">
                                <i class="bi bi-exclamation-triangle-fill me-1"></i>
                                {{ $errors->first('credencial') ?: $errors->first('password') }}
                            </div>
                        @endif

                        <!-- Formulario -->
                        <form method="POST" action="{{ route('login.post') }}" id="loginForm">
                            @csrf

                            <!-- Credencial (Email o Ficha) -->
                            <div class="mb-3">
                                <div class="input-group">
                                    <span class="input-group-text bg-white border-end-0">
                                        <i class="bi bi-person text-secondary"></i>
                                    </span>
                                    <input
                                        type="text"
                                        name="credencial"
                                        class="form-control border-start-0 @error('credencial') is-invalid @enderror"
                                        placeholder="Correo electrónico o ficha de usuario"
                                        value="{{ old('credencial') }}"
                                        autocomplete="username"
                                        autofocus
                                        required
                                    >
                                </div>
                            </div>

                            <!-- Contraseña con toggle -->
                            <div class="mb-3">
                                <div class="input-group">
                                    <span class="input-group-text bg-white border-end-0">
                                        <i class="bi bi-lock text-secondary"></i>
                                    </span>
                                    <input
                                        type="password"
                                        name="password"
                                        id="passwordField"
                                        class="form-control border-start-0 border-end-0 @error('password') is-invalid @enderror"
                                        placeholder="Contraseña"
                                        autocomplete="current-password"
                                        required
                                    >
                                    <span class="input-group-text bg-white border-start-0" role="button" id="togglePassword">
                                        <i class="bi bi-eye text-secondary" id="eyeIcon"></i>
                                    </span>
                                </div>
                            </div>

                            <!-- Recordar + ¿Olvidaste? -->
                            <div class="d-flex justify-content-between align-items-center mb-4">
                                <div class="form-check">
                                    <input class="form-check-input" type="checkbox" name="recordar" id="recordar"
                                           {{ old('recordar') ? 'checked' : '' }}>
                                    <label class="form-check-label small text-secondary" for="recordar">Recordar</label>
                                </div>
                                <a href="{{ route('password.request') }}" class="forgot-link small text-decoration-none">
                                    ¿Olvidaste tu contraseña?
                                </a>
                            </div>

                            <!-- Botones responsivos con Bootstrap grid -->
                            <div class="row g-2">
                                <div class="col-12 col-sm-6 order-2 order-sm-1">
                                    <a href="{{ route('register') }}"
                                       class="btn btn-picade-green w-100 fw-bold text-uppercase py-2 small">
                                        <i class="bi bi-person-plus me-1 d-none d-md-inline"></i>
                                        Registrarse
                                    </a>
                                </div>
                                <div class="col-12 col-sm-6 order-1 order-sm-2">
                                    <button type="submit" id="btnLogin"
                                            class="btn btn-picade-blue w-100 fw-bold text-uppercase py-2 small">
                                        <span class="spinner-btn me-2"></span>
                                        <i class="bi bi-box-arrow-in-right me-1 d-none d-md-inline"></i>
                                        Iniciar Sesión
                                    </button>
                                </div>
                            </div>

                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- JavaScript de Bootstrap desde CDN -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js"></script>

    <script>
        // Toggle mostrar/ocultar contraseña
        document.getElementById('togglePassword').addEventListener('click', function () {
            const field = document.getElementById('passwordField');
            const icon  = document.getElementById('eyeIcon');
            if (field.type === 'password') {
                field.type = 'text';
                icon.classList.replace('bi-eye', 'bi-eye-slash');
            } else {
                field.type = 'password';
                icon.classList.replace('bi-eye-slash', 'bi-eye');
            }
        });

        // Spinner al enviar
        document.getElementById('loginForm').addEventListener('submit', function () {
            const btn = document.getElementById('btnLogin');
            btn.classList.add('loading');
            btn.disabled = true;
        });
    </script>

</body>
</html>
