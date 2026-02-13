   /**
     * █ MOTOR TRANSACCIONAL DE ALTA (STORE)
     * ─────────────────────────────────────────────────────────────────────────
     * Ejecuta la persistencia de un nuevo usuario en la base de datos de manera atómica.
     * Este es el método más crítico del ciclo de vida de la identidad.
     *
     * @security Critical Path (Ruta Crítica de Seguridad)
     * @audit    Event ID: USER_CREATION
     *
     * @param Request $request Objeto con los datos capturados en el formulario.
     * @return \Illuminate\Http\RedirectResponse Redirección con mensaje de estado.
     */
    public function store(Request $request)
    {
        // ─────────────────────────────────────────────────────────────────────
        // FASE 1: VALIDACIÓN DE INTEGRIDAD SINTÁCTICA (INPUT VALIDATION)
        // ─────────────────────────────────────────────────────────────────────
        // El método validate() actúa como un cortafuegos. Si algo falla aquí, 
        // Laravel detiene el script y devuelve al usuario al formulario con errores.
        $request->validate([
            // [Identificadores Únicos]
            // 'required': No puede estar vacío.
            // 'max:50': Previene ataques de desbordamiento de búfer en BD.
            'ficha'             => ['required', 'string', 'max:50'],
            
            // [Activos Multimedia]
            // 'image': Valida los "Magic Bytes" del archivo para asegurar que es una imagen real.
            // 'mimes': Solo permite extensiones seguras (evita .php, .exe disfrazados).
            'foto_perfil'       => ['nullable', 'image', 'mimes:jpg,jpeg,png', 'max:2048'],
            
            // [Credenciales]
            'email'             => ['required', 'string', 'email', 'max:255'],
            
            // [Seguridad]
            // 'confirmed': Busca un campo 'password_confirmation' y verifica que sean idénticos.
            'password'          => ['required', 'string', 'min:8', 'confirmed'],
            
            // [Datos Personales]
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            
            // [Relaciones (Foreign Keys)]
            // 'integer': Evita inyección de strings en campos numéricos.
            // 'min:1': Evita IDs inválidos (0 o negativos).
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['required', 'integer', 'min:1'],
            'id_centro_trabajo' => ['required', 'integer', 'min:1'],
            'id_departamento'   => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['required', 'integer', 'min:1'],
            
            // [Metadatos Opcionales]
            // 'nullable': Permite que el campo venga vacío o null.
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100']
        ]);

        // ─────────────────────────────────────────────────────────────────────
        // FASE 2: GESTIÓN DE ACTIVOS MULTIMEDIA (ASSET MANAGEMENT)
        // ─────────────────────────────────────────────────────────────────────
        
        // Inicializamos la variable en NULL. Si el usuario no sube foto, se envía NULL a la BD.
        $rutaFoto = null;

        // Verificamos si en la petición viene un archivo válido llamado 'foto_perfil'
        if ($request->hasFile('foto_perfil')) {
            
            // Generamos un nombre único: TIMESTAMP + FICHA + EXTENSIÓN
            // Ejemplo: 1715629900_598212.jpg
            // Esto evita que si dos usuarios suben "foto.jpg", una sobrescriba a la otra.
            $filename = time() . '_' . $request->ficha . '.' . $request->file('foto_perfil')->getClientOriginalExtension();
            
            // Guardamos físicamente el archivo en 'storage/app/public/perfiles'
            $path = $request->file('foto_perfil')->storeAs('perfiles', $filename, 'public');
            
            // Generamos la ruta pública accesible para el navegador
            $rutaFoto = '/storage/' . $path;
        }

        // ─────────────────────────────────────────────────────────────────────
        // FASE 3: EJECUCIÓN BLINDADA DE PROCEDIMIENTO ALMACENADO
        // ─────────────────────────────────────────────────────────────────────
        try {
            // Definimos la sentencia SQL.
            // Usamos '?' (Placeholders) para evitar INYECCIÓN SQL. 
            // Laravel escapará automáticamente cualquier caracter malicioso.
            // NOTA: Hay exactamente 19 signos de interrogación para los 19 parámetros.
            $sql = 'CALL SP_RegistrarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

            // Ejecutamos la consulta enviando el arreglo de datos en orden posicional estricto.
            $resultado = DB::select($sql, [
                
                // [1] AUDITORÍA
                Auth::id(),                      // Obtenemos el ID del Admin logueado para trazar quién hizo el registro.

                // [2] IDENTIDAD DIGITAL
                $request->ficha,                 // Número de empleado.
                $rutaFoto,                       // URL de la foto (o NULL). ESTA ES LA POSICIÓN 3 CORRECTA.

                // [3] IDENTIDAD HUMANA
                $request->nombre,                // Nombre de pila.
                $request->apellido_paterno,      // Apellido Paterno.
                $request->apellido_materno,      // Apellido Materno.
                $request->fecha_nacimiento,      // Fecha nacimiento (Validación de edad en SP).
                $request->fecha_ingreso,         // Fecha ingreso (Cálculo antigüedad en SP).

                // [4] CREDENCIALES
                $request->email,                 // Correo (Login).
                Hash::make($request->password),  // ENCRIPTACIÓN: Convertimos "123456" en "$2y$10$..." (Irreversible).

                // [5] ADSCRIPCIÓN (IDs numéricos)
                $request->id_rol,                // Rol de seguridad.
                $request->id_regimen,            // Régimen contractual.
                $request->id_puesto,             // Puesto.
                $request->id_centro_trabajo,     // Centro de Trabajo.
                $request->id_departamento,       // Departamento.
                $request->id_region,             // Región.
                $request->id_gerencia,           // Gerencia.

                // [6] METADATOS COMPLEMENTARIOS
                $request->nivel,                 // Nivel salarial.
                $request->clasificacion          // Clasificación.
            ]);

            // ─────────────────────────────────────────────────────────────────
            // FASE 4: RESPUESTA EXITOSA (SUCCESS HANDLER)
            // ─────────────────────────────────────────────────────────────────
            // Si llegamos aquí, el SP se ejecutó (COMMIT) correctamente.
            // Redirigimos al Index con un mensaje "toast" verde.
            return redirect()->route('usuarios.index')
                ->with('success', 'Colaborador registrado exitosamente. ID: #' . ($resultado[0]->Id_Usuario ?? 'OK'));

        } catch (\Illuminate\Database\QueryException $e) {
            // ─────────────────────────────────────────────────────────────────
            // FASE 5: MANEJO DE EXCEPCIONES Y LIMPIEZA (ROLLBACK & CLEANUP)
            // ─────────────────────────────────────────────────────────────────
            
            // [ANTI-ZOMBIE FILES]
            // Si la base de datos falla (ej: Ficha duplicada), la foto YA se subió en la Fase 2.
            // Debemos eliminarla físicamente para no dejar basura en el servidor.
            if ($rutaFoto && file_exists(public_path($rutaFoto))) {
                unlink(public_path($rutaFoto));
            }

            // [EXCEPTION MASKING]
            // El SP lanza errores técnicos (SIGNAL SQLSTATE). 
            // Usamos nuestros helpers para traducir "SQLSTATE[45000]..." a "La ficha ya existe".
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            // [STATE RESTORATION]
            // 'back()' devuelve al usuario al formulario.
            // 'withInput()' rellena los campos con lo que escribió (para que no tenga que escribir todo de nuevo).
            // 'with()' envía el mensaje de error para mostrar la alerta roja.
            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    Lo único que hay que agregar es la instrucción COLLATE utf8mb4_spanish_ci justo después de definir el tipo (VARCHAR) en cada parámetro de texto y en las variables internas de texto.