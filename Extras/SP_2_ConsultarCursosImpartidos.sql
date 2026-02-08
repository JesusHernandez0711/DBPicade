/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsultarCursosImpartidos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsultarCursosImpartidos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria			  : Trazabilidad de Carga Docente e Historial de Instrucción
   - Clasificación        : Consulta de Historial Docente (Instructor Record Inquiry)
   - Patrón de Diseño     : Targeted Version Snapshot (Snapshot de Versión Específica)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Capacitaciones

   II. PROPÓSITO Y VALOR DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es el pilar del Dashboard del Instructor. Permite al docente:
   1. GESTIÓN ACTUAL: Visualizar los cursos que tiene asignados y en ejecución.
   2. EVIDENCIA HISTÓRICA: Consultar cursos que ya impartió y fueron archivados.
   3. RESPONSABILIDAD: Garantizar que su nombre aparezca ligado únicamente a las versiones de curso 
      donde él fue el instructor titular, incluso si el curso tuvo múltiples reprogramaciones.

   III. LÓGICA DE FILTRADO INTELIGENTE (FORENSIC SNAPSHOT)
   ----------------------------------------------------------------------------------------------------------
   En un sistema transaccional dinámico, un curso puede cambiar de instructor entre versiones. 
   Para evitar que el historial de un instructor se "contamine" con datos de otros, el SP filtra por:
   
   - MAX(Id_DatosCap): Obtiene la versión más reciente de cada folio PERO condicionada a que 
     el instructor solicitado fuera el titular en esa versión específica.
   - SEMÁFORO DE VIGENCIA: Diferencia visualmente entre lo que es carga actual y lo que es historia.

   ========================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarCursosImpartidos`$$

CREATE PROCEDURE `SP_ConsultarCursosImpartidos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Instructor INT -- ID único del usuario con rol de instructor/capacitador.
)
ProcCursosImpart: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE IDENTIDAD
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio para recuperar el historial.' AS Mensaje,
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcCursosImpart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL DOCENTE (INSTRUCTION LOG ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- [BLOQUE 1: IDENTIFICADORES Y FOLIOS]
        `VC`.`Id_Capacitacion`,               -- PK del curso padre.
        `VC`.`Id_Detalle_de_Capacitacion`,     -- PK de la versión específica (Id_DatosCap).
        `VC`.`Numero_Capacitacion` AS `Folio_Curso`, -- Identificador institucional.
        
        -- [BLOQUE 2: METADATA ACADÉMICA]
        `VC`.`Nombre_Tema` AS `Tema_Curso`,    -- Contenido impartido.
        `VC`.`Duracion_Horas`,                 -- Valor curricular para el instructor.
        `VC`.`Clave_Gerencia_Solicitante`,     -- Área que recibe el beneficio.
        
        -- [BLOQUE 3: LOGÍSTICA DE OPERACIÓN]
        `VC`.`Nombre_Sede` AS `Sede`,          -- Ubicación del evento.
        `VC`.`Nombre_Modalidad` AS `Modalidad`, -- Método de entrega.
        `VC`.`Fecha_Inicio`,                   -- Apertura del curso.
        `VC`.`Fecha_Fin`,                      -- Cierre del curso.
        
        -- [BLOQUE 4: MÉTRICAS DE IMPACTO]
        `VC`.`Asistentes_Meta` AS `Cupo_Programado`,
        `VC`.`Total_Impacto_Real` AS `Asistentes_Confirmados`, -- Usamos la lógica del GREATEST calculada en la vista.
        `VC`.`Participantes_Activos`,          -- Total de alumnos vivos actualmente en lista.

        -- [BLOQUE 5: ESTADO Y CICLO DE VIDA]
        `VC`.`Estatus_Curso` AS `Estatus_Snapshot`, -- Estado operativo (En curso, Finalizado, etc).
        
        /* SEMÁFORO DE VIGENCIA DOCENTE 
           Diferencia registros de operación activa de los de archivo histórico. */
        CASE 
            WHEN `DC`.`Activo` = 1 THEN 'ACTUAL'
            ELSE 'HISTORIAL'
        END AS `Tipo_Registro`,

        /* BANDERA DE VISIBILIDAD (Soft Delete Check) 
           Permite al Frontend aplicar estilos (ej. opacidad) a registros archivados. */
        `DC`.`Activo` AS `Es_Version_Vigente`,

        -- [BLOQUE 6: AUDITORÍA]
        `DC`.`created_at` AS `Fecha_Asignacion`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    -- Unión con la tabla física para filtrar por el instructor titular de la versión.
    INNER JOIN `Picade`.`DatosCapacitaciones` `DC` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
        
    WHERE `DC`.`Fk_Id_Instructor` = _Id_Instructor
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA DE SNAPSHOT TITULAR (INSTRUCTOR-SPECIFIC MAX VERSION)
       Objetivo: Si un curso tuvo versiones con otros instructores, este subquery asegura que
       el instructor consultado solo vea la versión MÁS RECIENTE donde ÉL fue el responsable.
       ------------------------------------------------------------------------------------------------------ */
    AND `DC`.`Id_DatosCap` = (
        SELECT MAX(`DC2`.`Id_DatosCap`)
        FROM `Picade`.`DatosCapacitaciones` `DC2`
        WHERE `DC2`.`Fk_Id_Capacitacion` = `VC`.`Id_Capacitacion`
          AND `DC2`.`Fk_Id_Instructor` = _Id_Instructor
    )
    
    -- Ordenamos para mostrar la carga docente actual y reciente primero.
    ORDER BY `DC`.`Activo` DESC, `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

