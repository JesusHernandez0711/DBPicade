    /**
     * █ VISOR DE PERFIL PROPIO
     * ─────────────────────────────────────────────────────────────────────────
     * Muestra la información del usuario que tiene la sesión activa actualmente.
     *
     * @security Context Isolation
     * A diferencia de `show($id)`, este método NO recibe parámetros. Utiliza estrictamente
     * `Auth::id()` para la consulta. Esto impide que un usuario malintencionado pueda
     * ver el perfil de otro modificando el ID en la URL (IDOR Prevention).
     *
     * @return \Illuminate\View\View Vista del perfil personal.
     */
    public function perfil()
    {
        //try {
            $perfil = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);

            if (empty($perfil)) {
                return redirect('/Dashboard')
                    ->with('danger', 'Error de integridad: No se pudo cargar tu perfil asociado.');
            }

            $catalogos = $this->cargarCatalogos();

            return view('Usuario.perfil', [
                'perfil'    => $perfil[0],
                'catalogos' => $catalogos,
            ]);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect('/Dashboard')
                ->with('danger', $mensajeSP);
        }*/
    }

    /**
     * █ ACTUALIZACIÓN DE DATOS PERSONALES PROPIOS
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario corregir su información básica (Nombre, Dirección, Foto).
     *
     * @security Scope Limitation
     * Este método NO permite editar campos sensibles de administración como:
     * - Rol (Privilegios)
     * - Estatus (Activo/Inactivo)
     * - Email (Credencial) - Para esto ver `actualizarCredenciales`
     *
     * @param Request $request Datos del formulario de perfil.
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarPerfil(Request $request)
    {
        // 1. Validación de campos permitidos
        $request->validate([
            'ficha'             => ['required', 'string', 'max:10'],
            'nombre'            => ['required', 'string', 'max:100'],
            'apellido_paterno'  => ['required', 'string', 'max:100'],
            'apellido_materno'  => ['required', 'string', 'max:100'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        //try {
            // Ejecución del SP específico para auto-edición (limitado en alcance)
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(), // El ID sale de la sesión, no del Request (Seguridad Crítica)
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->id_regimen,
                $request->id_puesto ?? 0,
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Perfil actualizado.';
            return redirect()->route('MiPerfil')
                ->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }*/
    }

    /*
     * █ GESTIÓN DE CREDENCIALES (PASSWORD / EMAIL)
     * ─────────────────────────────────────────────────────────────────────────
     * Permite al usuario cambiar sus llaves de acceso al sistema.
     *
     * @security Double Verification (Anti-Hijacking)
     * Implementa un mecanismo de verificación de contraseña actual.
     * El usuario DEBE proporcionar su `password_actual` correcta para autorizar el cambio.
     * Esto mitiga el riesgo de "Session Hijacking" (si alguien deja la PC desbloqueada,
     * el atacante no puede cambiar la contraseña sin saber la actual).
     *
     * @param Request $request
     * @return \Illuminate\Http\RedirectResponse
     */
    public function actualizarCredenciales(Request $request)
    {
        // 1. Validación de input
        $request->validate([
            'password_actual' => ['required', 'string'],
            'nuevo_email'     => ['nullable', 'string', 'email', 'max:255'],
            'nueva_password'  => ['nullable', 'string', 'min:8', 'confirmed'],
        ], [
            'password_actual.required' => 'Por seguridad, debes ingresar tu contraseña actual para confirmar los cambios.',
        ]);

        // 2. Validación lógica: Debe haber al menos un dato para cambiar
        if (!$request->filled('nuevo_email') && !$request->filled('nueva_password')) {
            return back()->with('danger', 'No se detectaron cambios. Ingrese un nuevo correo o contraseña.');
        }

        // 3. VERIFICACIÓN DE IDENTIDAD (Hash Check)
        // Laravel compara el string plano del request con el hash bcrypt de la BD.
        $usuario = Auth::user();
        if (!Hash::check($request->password_actual, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'password_actual' => 'La contraseña actual es incorrecta. Intente nuevamente.',
            ]);
        }

        // 4. Preparación de datos (Sanitización)
        $nuevoEmailLimpio = $request->filled('nuevo_email') ? $request->nuevo_email : null;
        $nuevaPassHasheada = $request->filled('nueva_password') ? Hash::make($request->nueva_password) : null;

        // 5. Ejecución segura
        //try {
            $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
                Auth::id(),
                $nuevoEmailLimpio,
                $nuevaPassHasheada,
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Credenciales actualizadas correctamente.';
            return redirect()->route('MiPerfil')
                ->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return back()->with('danger', $mensajeSP);
        }*/
    }

    /*
     * █ INTERFAZ DE COMPLETADO DE EXPEDIENTE (ONBOARDING)
     * ─────────────────────────────────────────────────────────────────────────
     * Prepara el entorno para que el usuario finalice su registro de adscripción.
     * @data_context Consume SP_ConsultarPerfilPropio para la hidratación reactiva.
     * @return \Illuminate\View\View Vista `panel.CompletarPerfil`.
     */
    public function vistaCompletar()
    {
        //try {
            // 1. Hidratación del Snapshot (Carga Ligera vía SP)
            $resultado = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);
            
            if (empty($resultado)) {
                return redirect('/login')->with('danger', 'Error de hidratación: Sesión inválida.');
            }

            $perfil = $resultado[0];

            // 2. Carga de Catálogos Raíz (Regímenes, Puestos, Regiones, etc.)
            $catalogos = $this->cargarCatalogos();

            // Retornamos la vista física en resources/views/panel/CompletarPerfil.blade.php
            return view('panel.CompletarPerfil', compact('perfil', 'catalogos'));

        /*} catch (\Exception $e) {
            return redirect('/Dashboard')->with('danger', 'Error al inicializar el motor de integridad.');
        }*/
    }

    /**
     * █ MOTOR DE PERSISTENCIA DE ONBOARDING
     * ─────────────────────────────────────────────────────────────────────────
     * Procesa la actualización obligatoria consumiendo SP_EditarPerfilPropio.
     * @param Request $request Payload con los 16 parámetros requeridos por el SP.
     * @return \Illuminate\Http\RedirectResponse Redirección al Dashboard tras éxito.
     */
    public function guardarCompletado(Request $request)
    {
        // 1. Validación de Formato (Siguiendo tu estándar de actualizarPerfil)
        $request->validate([
            'ficha'            => ['required', 'string', 'max:10'],
            'foto_perfil'      => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'], // █ CLAVE: Validar como imagen
            'nombre'           => ['required', 'string', 'max:100'],
            'apellido_paterno' => ['required', 'string', 'max:100'],
            'apellido_materno' => ['required', 'string', 'max:100'],
            'fecha_nacimiento' => ['required', 'date'],
            'fecha_ingreso'    => ['required', 'date'],
            'id_regimen'       => ['required', 'integer', 'min:1'],
            'id_region'        => ['required', 'integer', 'min:1'],
            'id_puesto'        => ['nullable', 'integer'],
            'id_centro_trabajo'=> ['nullable', 'integer'],
            'id_departamento'  => ['nullable', 'integer'],
            'id_gerencia'      => ['nullable', 'integer'],
            'nivel'            => ['nullable', 'string', 'max:50'],
            'clasificacion'    => ['nullable', 'string', 'max:100'],
        ]);

        // 2. GESTIÓN DE ACTIVOS MULTIMEDIA (ASSET MANAGEMENT)
        $rutaFoto = null;
        if ($request->hasFile('foto_perfil')) {
            // Generación de nombre único para evitar colisiones
            $filename = time() . '_' . trim($request->ficha) . '.' . $request->file('foto_perfil')->getClientOriginalExtension();
            $path = $request->file('foto_perfil')->storeAs('perfiles', $filename, 'public');
            $rutaFoto = '/storage/' . $path;
        }

        //try {
            // 2. Ejecución Atómica (16 Parámetros en orden estricto)
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                // 1. _Id_Usuario_Sesion
                $request->ficha,           // 2. _Ficha
                $rutaFoto,     // 3. _Url_Foto
                $request->nombre,          // 4. _Nombre
                $request->apellido_paterno, // 5. _Apellido_Paterno
                $request->apellido_materno, // 6. _Apellido_Materno
                $request->fecha_nacimiento, // 7. _Fecha_Nacimiento
                $request->fecha_ingreso,    // 8. _Fecha_Ingreso
                $request->id_regimen,      // 9. _Id_Regimen
                $request->id_puesto ?? 0,  // 10. _Id_Puesto (Norm: 0 -> NULL)
                $request->id_centro_trabajo ?? 0, // 11. _Id_CentroTrabajo
                $request->id_departamento ?? 0,   // 12. _Id_Departamento
                $request->id_region,       // 13. _Id_Region
                $request->id_gerencia ?? 0, // 14. _Id_Gerencia
                $request->nivel,           // 15. _Nivel
                $request->clasificacion    // 16. _Clasificacion
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Perfil activado correctamente.';
            
            // 3. Liberación: El usuario ya puede ver su Dashboard
            return redirect()->route('dashboard')->with('success', $mensaje);

        /*} catch (\Illuminate\Database\QueryException $e) {
            // 4. FASE DE LIMPIEZA (ANTI-ZOMBIE CLEANUP)
            // Si la base de datos falla (ej: ficha duplicada), borramos la foto que acabamos de subir.
            if ($rutaFoto && file_exists(public_path($rutaFoto))) {
                unlink(public_path($rutaFoto));
            }

            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }*/
    }