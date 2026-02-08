
/* ======================================================================================================
   PROCEDIMIENTO 6: SP_Obtener_Participantes_Capacitacion
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Obtener la lista completa de participantes de una capacitación específica.
   Alimenta el grid de "Gestión de Participantes" en el módulo de Coordinador.
   
   INCLUYE:
   - Información completa del participante
   - Estatus actual (INSCRITO, ASISTIÓ, APROBADO, REPROBADO, BAJA)
   - Calificación y asistencia
   - Indicador visual de cupo
   
   ====================================================================================================== */

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Obtener_Participantes_Capacitacion`$$
CREATE PROCEDURE `SP_Obtener_Participantes_Capacitacion`(
    IN _Id_Detalle_Capacitacion INT
)
ProcPartCapac: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Existe INT DEFAULT 0;
    DECLARE v_Folio VARCHAR(100) DEFAULT '';
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Participantes_Activos INT DEFAULT 0;
    DECLARE v_Participantes_Baja INT DEFAULT 0;
    
    -- Constantes
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       VALIDACIÓN DE INPUT
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 'ERROR [400]: El ID del Detalle de Capacitación es obligatorio.' AS Mensaje;
        LEAVE ProcPartCapac; -- ← Usar la etiqueta
    END IF;
    
    -- Verificar existencia
    SELECT COUNT(*) INTO v_Existe
    FROM DatosCapacitaciones WHERE Id_DatosCap = _Id_Detalle_Capacitacion;
    
    IF v_Existe = 0 THEN
        SELECT 'ERROR [404]: La capacitación especificada no existe.' AS Mensaje;
        LEAVE ProcPartCapac; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       RESULTSET 1: RESUMEN DE CUPO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- Obtener métricas de cupo
    SELECT 
        C.Numero_Capacitacion,
        C.Asistentes_Programados
    INTO v_Folio, v_Cupo_Maximo
    FROM DatosCapacitaciones DC
    INNER JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    WHERE DC.Id_DatosCap = _Id_Detalle_Capacitacion;
    
    -- Contar participantes activos (no BAJA)
    SELECT COUNT(*) INTO v_Participantes_Activos
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = _Id_Detalle_Capacitacion
      AND Fk_Id_CatEstPart != c_ESTATUS_BAJA;
    
    -- Contar participantes de baja
    SELECT COUNT(*) INTO v_Participantes_Baja
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = _Id_Detalle_Capacitacion
      AND Fk_Id_CatEstPart = c_ESTATUS_BAJA;
    
    -- Devolver resumen
    SELECT 
        v_Folio                                     AS Folio_Curso,
        v_Cupo_Maximo                               AS Cupo_Maximo,
        v_Participantes_Activos                     AS Participantes_Activos,
        v_Participantes_Baja                        AS Participantes_Baja,
        (v_Participantes_Activos + v_Participantes_Baja) AS Total_Registros,
        (v_Cupo_Maximo - v_Participantes_Activos)   AS Cupo_Disponible,
        CASE 
            WHEN v_Participantes_Activos >= v_Cupo_Maximo THEN 'LLENO'
            WHEN v_Participantes_Activos >= (v_Cupo_Maximo * 0.8) THEN 'CASI_LLENO'
            ELSE 'DISPONIBLE'
        END                                         AS Estado_Cupo;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       RESULTSET 2: LISTA DETALLADA DE PARTICIPANTES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        /* ═══ IDENTIFICADORES ═══ */
        CP.Id_CapPart                               AS Id_Registro_Participante,
        U.Id_Usuario                                AS Id_Usuario,
        U.Ficha                                     AS Ficha_Participante,
        
        /* ═══ DATOS PERSONALES ═══ */
        IP.Apellido_Paterno                         AS Apellido_Paterno,
        IP.Apellido_Materno                         AS Apellido_Materno,
        IP.Nombre                                   AS Nombre,
        CONCAT(IP.Apellido_Paterno, ' ', IP.Apellido_Materno, ' ', IP.Nombre) 
                                                    AS Nombre_Completo,
        
        /* ═══ CONTEXTO ORGANIZACIONAL ═══ */
        G.Clave                                     AS Gerencia_Participante,
        
        /* ═══ RESULTADOS ═══ */
        CP.PorcentajeAsistencia                     AS Porcentaje_Asistencia,
        CP.Calificacion                             AS Calificacion,
        
        /* ═══ ESTATUS ═══ */
        EP.Id_CatEstPart                            AS Id_Estatus,
        EP.Codigo                                   AS Codigo_Estatus,
        EP.Nombre                                   AS Estatus_Participante,
        EP.Descripcion                              AS Descripcion_Estatus,
        
        /* ═══ INDICADORES VISUALES ═══ */
        CASE EP.Id_CatEstPart
            WHEN 1 THEN 'info'      -- INSCRITO
            WHEN 2 THEN 'primary'   -- ASISTIÓ
            WHEN 3 THEN 'success'   -- APROBADO
            WHEN 4 THEN 'danger'    -- REPROBADO
            WHEN 5 THEN 'secondary' -- BAJA
            ELSE 'default'
        END                                         AS Badge_Color,
        
        CASE 
            WHEN EP.Id_CatEstPart = c_ESTATUS_BAJA THEN 0
            ELSE 1
        END                                         AS Es_Participante_Activo
        
    FROM Capacitaciones_Participantes CP
    
    INNER JOIN Usuarios U 
        ON CP.Fk_Id_Usuario = U.Id_Usuario
    
    INNER JOIN Info_Personal IP 
        ON U.Fk_Id_InfoPer = IP.Id_InfoPer
    
    INNER JOIN Cat_Estatus_Participante EP 
        ON CP.Fk_Id_CatEstPart = EP.Id_CatEstPart
    
    LEFT JOIN Cat_Gerencias_Activos G 
        ON U.Fk_Id_CatGeren = G.Id_CatGeren
    
    WHERE 
        CP.Fk_Id_DatosCap = _Id_Detalle_Capacitacion
        
    ORDER BY 
        -- Primero los activos, luego las bajas
        CASE WHEN EP.Id_CatEstPart = c_ESTATUS_BAJA THEN 1 ELSE 0 END,
        -- Luego por apellido
        IP.Apellido_Paterno, 
        IP.Apellido_Materno, 
        IP.Nombre;

END$$

DELIMITER ;