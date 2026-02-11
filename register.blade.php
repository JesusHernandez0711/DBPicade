{{-- resources/views/auth/register.blade.php --}}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - Registro</title>
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
            min-height: 100vh;
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
            background: rgba(255, 255, 255, 0.85);
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

        .section-label {
            color: #1a3a5c;
            border-bottom: 2px solid #2d6aa0;
            display: inline-block;
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

        .btn-outline-secondary:hover {
            transform: translateY(-1px);
        }

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
         col-11      → móvil
         col-sm-10   → ≥576px
         col-md-8    → ≥768px
         col-lg-7    → ≥992px
         col-xl-6    → ≥1200px
         (más ancho que login porque el form tiene más campos)
         =================================================================== -->
    <div class="d-flex align-items-center justify-content-center position-relative py-4" style="min-height:100vh; z-index:10;">
        <div class="container">
            <div class="row justify-content-center">
                <div class="col-11 col-sm-10 col-md-8 col-lg-7 col-xl-6">
                    <div class="glass-card rounded-4 shadow-lg p-4 p-md-5">

                        <!-- Título -->
                        <h1 class="login-title text-center fw-bold fs-2 mb-1">PICADE</h1>
                        <p class="text-center text-secondary small mb-4">Crear cuenta nueva</p>

                        <!-- Alerta de errores del SP -->
                        @if($errors->has('sp_error'))
                            <div class="alert alert-danger py-2 small">
                                <i class="bi bi-exclamation-triangle-fill me-1"></i>
                                {{ $errors->first('sp_error') }}
                            </div>
                        @endif

                        <!-- Formulario -->
                        <form method="POST" action="{{ route('register.post') }}" id="registerForm">
                            @csrf

                            <!-- ==============================
                                 SECCIÓN 1: Datos de Acceso
                                 ============================== -->
                            <h6 class="section-label fw-bold mb-3 pb-1">
                                <i class="bi bi-key me-1"></i> Datos de Acceso
                            </h6>

                            <div class="row g-3 mb-4">
                                <!-- Ficha -->
                                <div class="col-12 col-md-6">
                                    <label for="ficha" class="form-label small fw-semibold text-secondary">
                                        Ficha de empleado <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-person-badge text-secondary"></i>
                                        </span>
                                        <input type="text" name="ficha" id="ficha"
                                               class="form-control @error('ficha') is-invalid @enderror"
                                               value="{{ old('ficha') }}"
                                               placeholder="Ej: 12345"
                                               required>
                                    </div>
                                    @error('ficha')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Email -->
                                <div class="col-12 col-md-6">
                                    <label for="email" class="form-label small fw-semibold text-secondary">
                                        Correo electrónico <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-envelope text-secondary"></i>
                                        </span>
                                        <input type="email" name="email" id="email"
                                               class="form-control @error('email') is-invalid @enderror"
                                               value="{{ old('email') }}"
                                               placeholder="correo@pemex.com"
                                               required>
                                    </div>
                                    @error('email')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Contraseña -->
                                <div class="col-12 col-md-6">
                                    <label for="password" class="form-label small fw-semibold text-secondary">
                                        Contraseña <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-lock text-secondary"></i>
                                        </span>
                                        <input type="password" name="password" id="password"
                                               class="form-control @error('password') is-invalid @enderror"
                                               placeholder="Mínimo 8 caracteres"
                                               required>
                                    </div>
                                    @error('password')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Confirmar Contraseña -->
                                <div class="col-12 col-md-6">
                                    <label for="password_confirmation" class="form-label small fw-semibold text-secondary">
                                        Confirmar Contraseña <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-lock-fill text-secondary"></i>
                                        </span>
                                        <input type="password" name="password_confirmation" id="password_confirmation"
                                               class="form-control"
                                               placeholder="Repite la contraseña"
                                               required>
                                    </div>
                                </div>
                            </div>

                            <!-- ==============================
                                 SECCIÓN 2: Datos Personales
                                 ============================== -->
                            <h6 class="section-label fw-bold mb-3 pb-1">
                                <i class="bi bi-person-lines-fill me-1"></i> Datos Personales
                            </h6>

                            <div class="row g-3 mb-4">
                                <!-- Nombre -->
                                <div class="col-12 col-md-4">
                                    <label for="nombre" class="form-label small fw-semibold text-secondary">
                                        Nombre(s) <span class="text-danger">*</span>
                                    </label>
                                    <input type="text" name="nombre" id="nombre"
                                           class="form-control @error('nombre') is-invalid @enderror"
                                           value="{{ old('nombre') }}"
                                           placeholder="Nombre"
                                           required>
                                    @error('nombre')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Apellido Paterno -->
                                <div class="col-12 col-md-4">
                                    <label for="apellido_paterno" class="form-label small fw-semibold text-secondary">
                                        Apellido Paterno <span class="text-danger">*</span>
                                    </label>
                                    <input type="text" name="apellido_paterno" id="apellido_paterno"
                                           class="form-control @error('apellido_paterno') is-invalid @enderror"
                                           value="{{ old('apellido_paterno') }}"
                                           placeholder="Apellido Paterno"
                                           required>
                                    @error('apellido_paterno')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Apellido Materno -->
                                <div class="col-12 col-md-4">
                                    <label for="apellido_materno" class="form-label small fw-semibold text-secondary">
                                        Apellido Materno <span class="text-danger">*</span>
                                    </label>
                                    <input type="text" name="apellido_materno" id="apellido_materno"
                                           class="form-control @error('apellido_materno') is-invalid @enderror"
                                           value="{{ old('apellido_materno') }}"
                                           placeholder="Apellido Materno"
                                           required>
                                    @error('apellido_materno')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>
                            </div>

                            <!-- ==============================
                                 SECCIÓN 3: Información Laboral
                                 ============================== -->
                            <h6 class="section-label fw-bold mb-3 pb-1">
                                <i class="bi bi-briefcase me-1"></i> Información Laboral
                            </h6>

                            <div class="row g-3 mb-4">
                                <!-- Fecha de Nacimiento -->
                                <div class="col-12 col-md-6">
                                    <label for="fecha_nacimiento" class="form-label small fw-semibold text-secondary">
                                        Fecha de Nacimiento <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-calendar-event text-secondary"></i>
                                        </span>
                                        <input type="date" name="fecha_nacimiento" id="fecha_nacimiento"
                                               class="form-control @error('fecha_nacimiento') is-invalid @enderror"
                                               value="{{ old('fecha_nacimiento') }}"
                                               max="{{ now()->subYears(18)->format('Y-m-d') }}"
                                               required>
                                    </div>
                                    @error('fecha_nacimiento')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>

                                <!-- Fecha de Ingreso -->
                                <div class="col-12 col-md-6">
                                    <label for="fecha_ingreso" class="form-label small fw-semibold text-secondary">
                                        Fecha de Ingreso a PEMEX <span class="text-danger">*</span>
                                    </label>
                                    <div class="input-group">
                                        <span class="input-group-text bg-white">
                                            <i class="bi bi-calendar-check text-secondary"></i>
                                        </span>
                                        <input type="date" name="fecha_ingreso" id="fecha_ingreso"
                                               class="form-control @error('fecha_ingreso') is-invalid @enderror"
                                               value="{{ old('fecha_ingreso') }}"
                                               max="{{ now()->format('Y-m-d') }}"
                                               required>
                                    </div>
                                    @error('fecha_ingreso')
                                        <div class="text-danger small mt-1">{{ $message }}</div>
                                    @enderror
                                </div>
                            </div>

                            <!-- Botones responsivos -->
                            <div class="row g-2 mt-2">
                                <div class="col-12 col-sm-6 order-2 order-sm-1">
                                    <a href="{{ route('login') }}"
                                       class="btn btn-outline-secondary w-100 fw-bold text-uppercase py-2 small">
                                        <i class="bi bi-arrow-left me-1"></i>
                                        Volver al Login
                                    </a>
                                </div>
                                <div class="col-12 col-sm-6 order-1 order-sm-2">
                                    <button type="submit" id="btnRegister"
                                            class="btn btn-picade-green w-100 fw-bold text-uppercase py-2 small">
                                        <span class="spinner-btn me-2"></span>
                                        <i class="bi bi-person-check me-1 d-none d-md-inline"></i>
                                        Registrarse
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
        // Spinner al enviar
        document.getElementById('registerForm').addEventListener('submit', function () {
            const btn = document.getElementById('btnRegister');
            btn.classList.add('loading');
            btn.disabled = true;
        });

        // Validación temporal: fecha_ingreso >= fecha_nacimiento
        document.getElementById('fecha_ingreso').addEventListener('change', function () {
            const nacimiento = document.getElementById('fecha_nacimiento').value;
            if (nacimiento && this.value < nacimiento) {
                this.setCustomValidity('La fecha de ingreso no puede ser anterior a la fecha de nacimiento.');
                this.reportValidity();
            } else {
                this.setCustomValidity('');
            }
        });
    </script>

</body>
</html>
