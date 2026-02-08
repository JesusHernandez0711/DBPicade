USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   VERSIÓN: 4.0 (FULL 360° VIEW: CONTEXT + PARTICIPANTS + HISTORY LOG)
   ====================================================================================================
   
   1. OBJETIVO DE NEGOCIO
   ----------------------
   Proveer la información total de un curso para la pantalla de "Detalle y Auditoría".
   Permite al Coordinador responder 3 preguntas en una sola pantalla:
     1. "¿Cuál es el estado actual del curso?" (ResultSet 1).
     2. "¿Quiénes están asistiendo?" (ResultSet 2).
     3. "¿Qué cambios ha sufrido este curso en el tiempo?" (ResultSet 3).

   2. ESTRATEGIA TÉCNICA: "PARENT-CHILD DISCOVERY"
   -----------------------------------------------
   Para mostrar el historial, el SP primero identifica el `Id_Capacitacion` (Padre) del detalle solicitado.
   Luego, usa ese ID Padre para buscar todos los registros hermanos (versiones anteriores) en la 
   tabla `DatosCapacitaciones`.

   3. CONTRATO DE SALIDA (3 RESULTSETS)
   ------------------------------------
   [RESULTSET 1: HEADER] (1 Fila) - Datos actuales, IDs para edición y Auditoría del registro actual.
   [RESULTSET 2: BODY]   (N Filas) - Lista Nominal de Participantes.
   [RESULTSET 3: FOOTER] (N Filas) - Bitácora Histórica (Timeline de cambios).

   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] ID de la versión que se quiere consultar
)
BEGIN
    /* Variable para almacenar el ID del "Folder" (Padre) y buscar la historia completa */
    DECLARE v_Id_Padre_Capacitacion INT;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN Y DESCUBRIMIENTO DEL PADRE
       ============================================================================================ */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID inválido.';
    END IF;

    -- Obtenemos el ID del Padre. Si no existe, esto también sirve como validación de existencia.
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación no existe.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: [RESULTSET 1] EL EXPEDIENTE ACTUAL (HEADER)
       Datos para visualización y precarga de formulario de edición.
       ============================================================================================ */
    SELECT 
        /* DATOS DE IDENTIDAD (INMUTABLES) */
        `VC`.`Id_Capacitacion`             AS `Id_Padre`,
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia_Texto`, 
        `VC`.`Nombre_Tema`                 AS `Tema_Texto`,     
        `VC`.`Tipo_Instruccion`            AS `Tipo_Texto`,
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado`, 

        /* DATOS MUTABLES (PAREJAS ID/TEXTO PARA EDICIÓN) */
        `DC`.`Id_DatosCap`                 AS `Id_Detalle`, 
        
        -- Configuración Actual
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`,
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor_Texto`,
        
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        `VC`.`Nombre_Sede`                 AS `Sede_Texto`,
        
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad_Texto`,
        
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Para colorear el badge del estado actual

        -- Datos Operativos
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Observaciones`               AS `Bitacora_Notas`, -- Justificación de ESTA versión
        `DC`.`AsistentesReales`            AS `Asistentes_Reales_Manual`,
        `VC`.`Duracion_Horas`,

        -- Auditoría de ESTA Versión
        `DC`.`created_at`                  AS `Fecha_Creacion_Registro`,
        `DC`.`updated_at`                  AS `Fecha_Ultima_Edicion`,
        CONCAT(IFNULL(`IP_Crt`.`Apellido_Paterno`,''), ' ', IFNULL(`IP_Crt`.`Apellido_Materno`,''), ' ', IFNULL(`IP_Crt`.`Nombre`,'')) AS `Creado_Por_Nombre`,
        `U_Crt`.`Ficha`                    AS `Creado_Por_Ficha`

    FROM `Picade`.`DatosCapacitaciones` `DC`
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    LEFT JOIN `Picade`.`Usuarios` `U_Crt` ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Crt`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Crt` ON `U_Crt`.`Fk_Id_InfoPersonal` = `IP_Crt`.`Id_InfoPersonal`
    
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ============================================================================================
       BLOQUE 3: [RESULTSET 2] LISTA DE PARTICIPANTES (BODY)
       Alumnos inscritos en esta capacitación.
       ============================================================================================ */
    SELECT 
        `Id_Registro_Participante`    AS `Id_Inscripcion`,
        `Ficha_Participante`          AS `Ficha`,
        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        `Resultado_Final`             AS `Estatus_Alumno`,
        `Detalle_Resultado`           AS `Descripcion_Estatus`
    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ============================================================================================
       BLOQUE 4: [RESULTSET 3] BITÁCORA HISTÓRICA (FOOTER)
       Historial completo de cambios (Timeline). Muestra todas las versiones que ha tenido este Folio.
       ============================================================================================ */
    SELECT 
        /* ID de la versión histórica */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`,
        
        /* ¿Cuándo ocurrió el cambio? */
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        
        /* ¿Quién hizo el cambio? (Responsable) */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* LA JUSTIFICACIÓN (Vital para la auditoría) */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* La Fotografía de ese momento (Snapshot) */
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_Asignado`,
        `H_VC`.`Nombre_Sede`                AS `Sede_Asignada`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* Bandera para resaltar cuál es la versión que estamos viendo actualmente en el Header */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera para saber cuál es la versión VIGENTE real (la última activa) */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC` -- Usamos la vista para no re-hacer joins de nombres
    
    /* Join manual para sacar el nombre del responsable de ESA versión histórica */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U` ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP` ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`

    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion -- Filtramos por el PADRE para traer a todos los hermanos
    
    /* Ordenamos cronológicamente inverso: Lo más reciente arriba */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;