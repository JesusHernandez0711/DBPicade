/* ======================================================================================================
   PROCEDIMIENTO 4: SP_Obtener_Mis_Cursos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Alimentar la sección "Mi Historial de Capacitación" en el Perfil del Usuario (Participante).
   Muestra ÚNICAMENTE la última versión (vigente) de cada capacitación para evitar duplicados.
   
   ARQUITECTURA:
   -------------
   Implementa el patrón "Latest Snapshot" para garantizar que cada capacitación aparezca
   solo UNA vez, mostrando la información más actualizada.
   
   ====================================================================================================== */

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Obtener_Mis_Cursos`$$
CREATE PROCEDURE `SP_Obtener_Mis_Cursos`(
    IN _Id_Usuario INT
)
ProcMisCursos: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       VALIDACIÓN DE INPUT
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 THEN
        SELECT 
            'ERROR [400]: El ID del Usuario es obligatorio para consultar el historial.' AS Mensaje;
        LEAVE ProcMisCursos; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       CONSULTA PRINCIPAL - PATRÓN LATEST SNAPSHOT
       ═══════════════════════════════════════════════════════════════════════════════════
       
       LÓGICA:
       1. Obtener todas las capacitaciones donde el usuario es participante
       2. Filtrar para mostrar solo la ÚLTIMA VERSIÓN de cada capacitación padre
       3. Incluir información del registro de participante correspondiente
       
       NOTA IMPORTANTE:
       El usuario puede estar inscrito en MÚLTIPLES VERSIONES de la misma capacitación
       (si hubo reprogramaciones y migración de participantes). Aquí mostramos SOLO
       la versión más reciente donde está inscrito.
       
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        /* ═══ BLOQUE 1: IDENTIFICADORES ═══ */
        C.Id_Capacitacion                   AS Id_Capacitacion,
        DC.Id_DatosCap                      AS Id_Detalle_Capacitacion,
        CP.Id_CapPart                       AS Id_Registro_Participante,
        C.Numero_Capacitacion               AS Folio_Curso,
        
        /* ═══ BLOQUE 2: INFORMACIÓN DEL CURSO ═══ */
        TC.Nombre AS Tema_Curso,
        TC.Duracion_Horas                   AS Duracion_Horas,
        
        /* ═══ BLOQUE 3: LOGÍSTICA ═══ */
        S.Nombre AS Sede,
        MC.Nombre                           AS Modalidad,
        CONCAT(IP_Inst.Apellido_Paterno, ' ', IP_Inst.Apellido_Materno, ' ', IP_Inst.Nombre) 
                                            AS Instructor_Asignado,
        
        /* ═══ BLOQUE 4: FECHAS ═══ */
        DC.Fecha_Inicio                     AS Fecha_Inicio,
        DC.Fecha_Fin                        AS Fecha_Fin,
        
        /* ═══ BLOQUE 5: ESTATUS DEL CURSO ═══ */
        EC.Nombre                           AS Estatus_Curso,
        DC.Activo                           AS Curso_Activo,
        
        /* ═══ BLOQUE 6: MIS RESULTADOS ═══ */
        CP.PorcentajeAsistencia             AS Mi_Porcentaje_Asistencia,
        CP.Calificacion                     AS Mi_Calificacion,
        EP.Nombre                           AS Mi_Resultado,
        EP.Descripcion                      AS Detalle_Resultado,
        
        /* ═══ BLOQUE 7: METADATA ═══ */
        DC.created_at                       AS Fecha_Ultima_Actualizacion
        
    FROM Capacitaciones_Participantes CP
    
    /* Enlace al detalle de la capacitación */
    INNER JOIN DatosCapacitaciones DC 
        ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
    
    /* Enlace a la cabecera (padre) */
    INNER JOIN Capacitaciones C 
        ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    
    /* Enlace al tema del curso */
    INNER JOIN Cat_Temas_Capacitacion TC 
        ON C.Fk_Id_Cat_TemasCap = TC.Id_Cat_TemasCap
    
    /* Enlace a la sede */
    INNER JOIN Cat_Cases_Sedes S 
        ON DC.Fk_Id_CatCases_Sedes = S.Id_CatCases_Sedes
    
    /* Enlace a la modalidad */
    INNER JOIN Cat_Modalidad_Capacitacion MC 
        ON DC.Fk_Id_CatModalCap = MC.Id_CatModalCap
    
    /* Enlace al estatus del curso */
    INNER JOIN Cat_Estatus_Capacitacion EC 
        ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
    
    /* Enlace al estatus del participante */
    INNER JOIN Cat_Estatus_Participante EP 
        ON CP.Fk_Id_CatEstPart = EP.Id_CatEstPart
    
    /* Enlace al instructor */
    INNER JOIN Usuarios U_Inst 
        ON DC.Fk_Id_Instructor = U_Inst.Id_Usuario
    INNER JOIN Info_Personal IP_Inst 
        ON U_Inst.Fk_Id_InfoPer = IP_Inst.Id_InfoPer
    
    WHERE 
        /* 1. Filtro de Seguridad: Solo registros de este usuario */
        CP.Fk_Id_Usuario = _Id_Usuario
        
        /* 2. Filtro Latest Snapshot: Solo la versión más reciente de cada capacitación */
        AND DC.Id_DatosCap = (
            SELECT MAX(DC2.Id_DatosCap)
            FROM Capacitaciones_Participantes CP2
            INNER JOIN DatosCapacitaciones DC2 ON CP2.Fk_Id_DatosCap = DC2.Id_DatosCap
            WHERE DC2.Fk_Id_Capacitacion = C.Id_Capacitacion
              AND CP2.Fk_Id_Usuario = _Id_Usuario
        )
        
    ORDER BY 
        DC.Fecha_Inicio DESC;  -- Lo más reciente arriba

END$$
DELIMITER ;