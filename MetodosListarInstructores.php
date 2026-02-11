
    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 4: LISTADOS PARA DROPDOWNS Y REPORTES
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * LISTAR INSTRUCTORES ACTIVOS (PARA DROPDOWNS DE ASIGNACIÓN)
     * SP UTILIZADO: SP_ListarInstructoresActivos
     * RETORNA: JSON [{Id_Usuario, Ficha, Nombre_Completo}]
     */
    public function listarInstructoresActivos()
    {
        try {
            $instructores = DB::select('CALL SP_ListarInstructoresActivos()');
            return response()->json($instructores);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json(['error' => 'Error al cargar la lista de instructores.'], 500);
        }
    }

    /**
     * LISTAR TODOS LOS INSTRUCTORES (HISTORIAL COMPLETO)
     * SP UTILIZADO: SP_ListarTodosInstructores_Historial
     * RETORNA: JSON [{Id_Usuario, Ficha, Nombre_Completo_Filtro}]
     */
    public function listarInstructoresHistorial()
    {
        try {
            $instructores = DB::select('CALL SP_ListarTodosInstructores_Historial()');
            return response()->json($instructores);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json(['error' => 'Error al cargar el historial de instructores.'], 500);
        }
    }