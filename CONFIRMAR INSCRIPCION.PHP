/*
     * █ MÓDULO: TRANSACCIÓN DE INSCRIPCIÓN — PROCESADOR TRANSACCIONAL
     * ──────────────────────────────────────────────────────────────────────
     * @description: Gestiona el envío de la solicitud de inscripción de un 
     * trabajador. Delega la lógica de negocio pesimista al motor MariaDB.
     * * @protocol: ACID (Atomicity, Consistency, Isolation, Durability).
     * @security: Implementa protección contra CSRF y validación de tipos.
     * * @param Request $request: Contiene el `id_capacitacion` inyectado por el modal.
     * @return \Illuminate\Http\RedirectResponse (Redirección con Flash Message).
     *
    public function confirmarInscripcion(Request $request)
    {
        // 1. VALIDACIÓN FORENSE DE ENTRADA
        // Asegura que el ID recibido sea un entero positivo, mitigando ataques de inyección.
        $request->validate(['id_capacitacion' => 'required|integer|min:1']);

        try {
            // 2. EJECUCIÓN DE PROCEDIMIENTO ALMACENADO (DB BRIDGE)
            // Se invoca el SP_RegistrarParticipacionCapacitacion pasando:
            // - ID del Usuario (Extraído de la Sesión Segura).
            // - ID de la Capacitación (Extraído del Request).
            $resultado = DB::select('CALL SP_RegistrarParticipacionCapacitacion(?, ?)', [
                Auth::id(), 
                $request->id_capacitacion
            ]);

            /* 3. VERIFICACIÓN DE RESPUESTA (Protección contra pantalla en blanco)
            if (empty($resultado)) {
                return back()->with('danger', 'La base de datos no devolvió una respuesta válida.');
            }*

            // 3. EXTRACCIÓN DE RESULTADO OPERATIVO
            // El SP devuelve una tabla con columnas 'Accion' y 'Mensaje'.
            $res = $resultado[0];
            
            // 4. MAPEÓ DE SEMÁNTICA VISUAL (UX ALERT MAPPING)
            // Se determina el color de la notificación según la respuesta lógica del SP.
            $tipo = match($res->Accion) {
                'INSCRITO'    => 'success',  // Color Verde: Éxito total.
                'YA_INSCRITO' => 'warning',  // Color Amarillo: Acción redundante pero segura.
                'CUPO_LLENO'  => 'danger',   // Color Rojo: Denegación por límites físicos.
                default       => 'info'      // Color Azul: Casos informativos.
            };

            // 5. CIERRE DE TRANSACCIÓN Y FEEDBACK
            // Redirige al Dashboard con el mensaje oficial emitido por la base de datos.
            //return redirect()->route('dashboard')->with($tipo, $res->Mensaje);
            return back()->with($tipo, $res->Mensaje);

        } catch (\Exception $e) {
            // 6. MANEJO DE EXCEPCIONES TÉCNICAS (FAIL-SAFE)
            // En caso de caída de BD o error de sintaxis, se informa sin exponer datos sensibles.
            //return redirect()->route('dashboard')->with('danger', 'ERROR CRÍTICO: El motor de inscripciones no está respondiendo.');
        }
    }

    /**
     * █ TRANSACCIÓN: REGISTRO DE INSCRIPCIÓN (STAGING)
     * ──────────────────────────────────────────────────────────────────────
     * Procesa el formulario del modal usando el SP de registro pesimista.
     */
    public function confirmarInscripcion(Request $request)
    {
        $request->validate(['id_capacitacion' => 'required|integer|min:1']);

        try {
            // Ejecución de la transacción atómica
            $resultado = DB::select('CALL SP_RegistrarParticipacionCapacitacion(?, ?)', [
                Auth::id(), 
                $request->id_capacitacion
            ]);

            if (empty($resultado)) {
                return back()->with('danger', 'La base de datos no emitió una respuesta válida.');
            }

            $res = $resultado[0];
            
            // Mapeo semántico de la respuesta del SP
            $tipo = match($res->Accion) {
                'INSCRITO'    => 'success',
                'YA_INSCRITO' => 'warning',
                'CUPO_LLENO'  => 'danger',
                'ESTATUS_INVALIDO' => 'danger',
                default       => 'info'
            };

            return back()->with($tipo, $res->Mensaje);

        } catch (\Exception $e) {
            return back()->with('danger', 'Error Crítico: El servicio de registro está temporalmente fuera de línea.');
        }
    }