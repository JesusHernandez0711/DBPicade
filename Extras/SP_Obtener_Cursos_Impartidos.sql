/* ======================================================================================================
   PROCEDIMIENTO 5: SP_Obtener_Cursos_Impartidos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Mostrar el historial de cursos que un instructor ha impartido.
   Útil para el perfil del instructor y para auditorías de carga docente.
   
   ARQUITECTURA:
   -------------
   Similar a SP_Obtener_Mis_Cursos pero filtrado por el campo Fk_Id_Instructor
   en lugar de la tabla de participantes.
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Obtener_Cursos_Impartidos`$$

CREATE PROCEDURE `SP_Obtener_Cursos_Impartidos`(
    IN _Id_Instructor INT
)
ProcCursosImpart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       VALIDACIÓN DE INPUT
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 
            'ERROR [400]: El ID del Instructor es obligatorio.' AS Mensaje;
        LEAVE ProcCursosImpart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       CONSULTA PRINCIPAL - CURSOS IMPARTIDOS (LATEST SNAPSHOT POR CAPACITACIÓN)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        /* ═══ BLOQUE 1: IDENTIFICADORES ═══ */
        C.Id_Capacitacion                   AS Id_Capacitacion,
        DC.Id_DatosCap                      AS Id_Detalle_Capacitacion,
        C.Numero_Capacitacion               AS Folio_Curso,
        
        /* ═══ BLOQUE 2: INFORMACIÓN DEL CURSO ═══ */
        TC.Nombre                           AS Tema_Curso,
        TC.Duracion_Horas                   AS Duracion_Horas,
        G.Clave                             AS Gerencia_Solicitante,
        
        /* ═══ BLOQUE 3: LOGÍSTICA ═══ */
        S.Nombre                            AS Sede,
        MC.Nombre                           AS Modalidad,
        
        /* ═══ BLOQUE 4: FECHAS ═══ */
        DC.Fecha_Inicio                     AS Fecha_Inicio,
        DC.Fecha_Fin                        AS Fecha_Fin,
        
        /* ═══ BLOQUE 5: MÉTRICAS ═══ */
        C.Asistentes_Programados            AS Cupo_Programado,
        DC.AsistentesReales                 AS Asistentes_Reales,
        (
            SELECT COUNT(*) 
            FROM Capacitaciones_Participantes CP 
            WHERE CP.Fk_Id_DatosCap = DC.Id_DatosCap
              AND CP.Fk_Id_CatEstPart != 5  -- Excluir BAJA
        )                                   AS Participantes_Activos,
        
        /* ═══ BLOQUE 6: ESTATUS ═══ */
        EC.Nombre                           AS Estatus_Curso,
        DC.Activo                           AS Curso_Activo,
        
        /* ═══ BLOQUE 7: METADATA ═══ */
        DC.created_at                       AS Fecha_Asignacion
        
    FROM DatosCapacitaciones DC
    
    /* Enlace a la cabecera */
    INNER JOIN Capacitaciones C 
        ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    
    /* Enlace al tema */
    INNER JOIN Cat_Temas_Capacitacion TC 
        ON C.Fk_Id_Cat_TemasCap = TC.Id_Cat_TemasCap
    
    /* Enlace a la gerencia */
    INNER JOIN Cat_Gerencias_Activos G 
        ON C.Fk_Id_CatGeren = G.Id_CatGeren
    
    /* Enlace a la sede */
    INNER JOIN Cat_Cases_Sedes S 
        ON DC.Fk_Id_CatCases_Sedes = S.Id_CatCases_Sedes
    
    /* Enlace a la modalidad */
    INNER JOIN Cat_Modalidad_Capacitacion MC 
        ON DC.Fk_Id_CatModalCap = MC.Id_CatModalCap
    
    /* Enlace al estatus */
    INNER JOIN Cat_Estatus_Capacitacion EC 
        ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
    
    WHERE 
        /* 1. Filtro: Solo cursos donde este usuario fue instructor */
        DC.Fk_Id_Instructor = _Id_Instructor
        
        /* 2. Latest Snapshot: Solo la versión más reciente donde fue instructor */
        AND DC.Id_DatosCap = (
            SELECT MAX(DC2.Id_DatosCap)
            FROM DatosCapacitaciones DC2
            WHERE DC2.Fk_Id_Capacitacion = C.Id_Capacitacion
              AND DC2.Fk_Id_Instructor = _Id_Instructor
        )
        
    ORDER BY 
        DC.Fecha_Inicio DESC;

END$$
DELIMITER ;
