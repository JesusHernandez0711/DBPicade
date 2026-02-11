{{-- resources/views/auth/register.blade.php --}}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>PICADE - Registro</title>

    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800&display=swap" rel="stylesheet">

    <style>
        *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

        html, body {
            min-height: 100vh;
            font-family: 'Montserrat', sans-serif;
        }

        /* ============================================================
           FONDO
           ============================================================ */
        .register-wrapper {
            position: relative;
            width: 100%;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 40px 16px;
        }

        .register-bg {
            position: fixed;
            inset: 0;
            background-image: url('{{ $bgImage }}');
            background-size: cover;
            background-position: center;
            z-index: 0;
        }

        .register-bg::after {
            content: '';
            position: absolute;
            inset: 0;
            background: linear-gradient(135deg, rgba(0,0,0,0.2) 0%, rgba(0,0,0,0.45) 100%);
        }

        /* ============================================================
           TARJETA DE REGISTRO
           ============================================================ */
        .register-card {
            position: relative;
            z-index: 10;
            width: 100%;
            max-width: 540px;
            padding: 36px 32px 28px;
            background: rgba(255, 255, 255, 0.88);
            backdrop-filter: blur(20px) saturate(160%);
            -webkit-backdrop-filter: blur(20px) saturate(160%);
            border-radius: 16px;
            border: 1px solid rgba(255, 255, 255, 0.5);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
            animation: slideUp 0.5s cubic-bezier(0.22, 1, 0.36, 1) forwards;
            opacity: 0;
            transform: translateY(24px);
        }

        @keyframes slideUp {
            to { opacity: 1; transform: translateY(0); }
        }

        /* ============================================================
           TÍTULO Y SUBTÍTULO
           ============================================================ */
        .reg-title {
            text-align: center;
            font-size: 1.8rem;
            font-weight: 800;
            letter-spacing: 3px;
            color: #1a3a5c;
            margin-bottom: 4px;
        }

        .reg-subtitle {
            text-align: center;
            font-size: 0.85rem;
            color: #6b7c93;
            margin-bottom: 24px;
            font-weight: 500;
        }

        /* ============================================================
           SECCIONES DEL FORMULARIO
           ============================================================ */
        .form-section {
            margin-bottom: 20px;
        }

        .section-label {
            font-size: 0.72rem;
            font-weight: 700;
            letter-spacing: 1.5px;
            text-transform: uppercase;
            color: #2d6aa0;
            margin-bottom: 10px;
            padding-bottom: 6px;
            border-bottom: 2px solid rgba(45, 106, 160, 0.15);
        }

        /* ============================================================
           GRID DE CAMPOS (2 columnas en desktop)
           ============================================================ */
        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }

        .form-row.single {
            grid-template-columns: 1fr;
        }

        .form-group {
            display: flex;
            flex-direction: column;
        }

        .form-label {
            font-size: 0.78rem;
            font-weight: 600;
            color: #4a5568;
            margin-bottom: 4px;
        }

        .form-input {
            width: 100%;
            padding: 11px 14px;
            font-family: 'Montserrat', sans-serif;
            font-size: 0.85rem;
            color: #333;
            background: rgba(255, 255, 255, 0.7);
            border: 1.5px solid #ccd5de;
            border-radius: 8px;
            outline: none;
            transition: all 0.25s ease;
        }

        .form-input::placeholder { color: #a0aec0; }

        .form-input:focus {
            border-color: #2d6aa0;
            background: #fff;
            box-shadow: 0 0 0 3px rgba(45, 106, 160, 0.1);
        }

        .form-input.is-invalid {
            border-color: #d9534f;
        }

        .error-text {
            color: #d9534f;
            font-size: 0.72rem;
            margin-top: 3px;
            font-weight: 500;
        }

        /* ============================================================
           ALERTA DE ERRORES DEL SP
           ============================================================ */
        .alert-error {
            background: rgba(217, 83, 79, 0.08);
            border: 1px solid rgba(217, 83, 79, 0.25);
            border-radius: 8px;
            padding: 10px 14px;
            margin-bottom: 16px;
            font-size: 0.82rem;
            color: #a94442;
            line-height: 1.5;
        }

        /* ============================================================
           BOTONES
           ============================================================ */
        .btn-row {
            display: flex;
            gap: 12px;
            margin-top: 24px;
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

        .btn-back {
            background: #78909c;
        }

        .btn-back:hover {
            background: #607d8b;
            transform: translateY(-1px);
        }

        .btn-submit {
            background: linear-gradient(135deg, #43a047, #2e7d32);
        }

        .btn-submit:hover {
            background: linear-gradient(135deg, #388e3c, #1b5e20);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(46, 125, 50, 0.35);
        }

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

        .btn.loading .spinner { display: inline-block; }

        @keyframes spin { to { transform: rotate(360deg); } }

        /* ============================================================
           RESPONSIVE
           ============================================================ */
        @media (max-width: 560px) {
            .form-row { grid-template-columns: 1fr; }
            .register-card { padding: 24px 20px; }
            .btn-row { flex-direction: column; }
        }
    </style>
</head>
<body>

<div class="register-wrapper">
    <div class="register-bg"></div>

    <div class="register-card">
        <h1 class="reg-title">PICADE</h1>
        <p class="reg-subtitle">Registro de nuevo usuario</p>

        {{-- Errores del SP --}}
        @if($errors->has('registro'))
            <div class="alert-error">{{ $errors->first('registro') }}</div>
        @endif

        <form method="POST" action="{{ route('register.post') }}" id="registerForm">
            @csrf

            {{-- SECCIÓN 1: Credenciales --}}
            <div class="form-section">
                <div class="section-label">Datos de acceso</div>

                <div class="form-row">
                    <div class="form-group">
                        <label class="form-label" for="ficha">Ficha de Usuario *</label>
                        <input type="text" name="ficha" id="ficha"
                               class="form-input @error('ficha') is-invalid @enderror"
                               placeholder="Ej: 316211"
                               value="{{ old('ficha') }}" required>
                        @error('ficha') <span class="error-text">{{ $message }}</span> @enderror
                    </div>

                    <div class="form-group">
                        <label class="form-label" for="email">Correo Electrónico *</label>
                        <input type="email" name="email" id="email"
                               class="form-input @error('email') is-invalid @enderror"
                               placeholder="tu.correo@pemex.com"
                               value="{{ old('email') }}" required>
                        @error('email') <span class="error-text">{{ $message }}</span> @enderror
                    </div>
                </div>

                <div class="form-row" style="margin-top: 12px;">
                    <div class="form-group">
                        <label class="form-label" for="password">Contraseña *</label>
                        <input type="password" name="password" id="password"
                               class="form-input @error('password') is-invalid @enderror"
                               placeholder="Mínimo 8 caracteres" required>
                        @error('password') <span class="error-text">{{ $message }}</span> @enderror
                    </div>

                    <div class="form-group">
                        <label class="form-label" for="password_confirmation">Confirmar Contraseña *</label>
                        <input type="password" name="password_confirmation" id="password_confirmation"
                               class="form-input"
                               placeholder="Repite tu contraseña" required>
                    </div>
                </div>
            </div>

            {{-- SECCIÓN 2: Datos Personales --}}
            <div class="form-section">
                <div class="section-label">Datos personales</div>

                <div class="form-row">
                    <div class="form-group">
                        <label class="form-label" for="nombre">Nombre(s) *</label>
                        <input type="text" name="nombre" id="nombre"
                               class="form-input @error('nombre') is-invalid @enderror"
                               value="{{ old('nombre') }}" required>
                        @error('nombre') <span class="error-text">{{ $message }}</span> @enderror
                    </div>

                    <div class="form-group">
                        <label class="form-label" for="apellido_paterno">Apellido Paterno *</label>
                        <input type="text" name="apellido_paterno" id="apellido_paterno"
                               class="form-input @error('apellido_paterno') is-invalid @enderror"
                               value="{{ old('apellido_paterno') }}" required>
                        @error('apellido_paterno') <span class="error-text">{{ $message }}</span> @enderror
                    </div>
                </div>

                <div class="form-row" style="margin-top: 12px;">
                    <div class="form-group">
                        <label class="form-label" for="apellido_materno">Apellido Materno *</label>
                        <input type="text" name="apellido_materno" id="apellido_materno"
                               class="form-input @error('apellido_materno') is-invalid @enderror"
                               value="{{ old('apellido_materno') }}" required>
                        @error('apellido_materno') <span class="error-text">{{ $message }}</span> @enderror
                    </div>

                    <div class="form-group">
                        {{-- Espacio reservado --}}
                    </div>
                </div>
            </div>

            {{-- SECCIÓN 3: Fechas --}}
            <div class="form-section">
                <div class="section-label">Información laboral</div>

                <div class="form-row">
                    <div class="form-group">
                        <label class="form-label" for="fecha_nacimiento">Fecha de Nacimiento *</label>
                        <input type="date" name="fecha_nacimiento" id="fecha_nacimiento"
                               class="form-input @error('fecha_nacimiento') is-invalid @enderror"
                               value="{{ old('fecha_nacimiento') }}" required>
                        @error('fecha_nacimiento') <span class="error-text">{{ $message }}</span> @enderror
                    </div>

                    <div class="form-group">
                        <label class="form-label" for="fecha_ingreso">Fecha de Ingreso *</label>
                        <input type="date" name="fecha_ingreso" id="fecha_ingreso"
                               class="form-input @error('fecha_ingreso') is-invalid @enderror"
                               value="{{ old('fecha_ingreso') }}" required>
                        @error('fecha_ingreso') <span class="error-text">{{ $message }}</span> @enderror
                    </div>
                </div>
            </div>

            {{-- BOTONES --}}
            <div class="btn-row">
                <a href="{{ route('login') }}" class="btn btn-back">
                    VOLVER AL LOGIN
                </a>
                <button type="submit" class="btn btn-submit" id="btnRegister">
                    <span class="spinner"></span>
                    REGISTRARSE
                </button>
            </div>
        </form>
    </div>
</div>

<script>
    document.getElementById('registerForm').addEventListener('submit', function() {
        const btn = document.getElementById('btnRegister');
        btn.classList.add('loading');
        btn.disabled = true;
    });
</script>

</body>
</html>
