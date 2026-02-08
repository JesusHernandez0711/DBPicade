DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarCapacitacionEspecifica`$$

CREATE PROCEDURE `SP_ConsultarCapacitacionEspecifica`(
    IN _Id_Detalle_Capacitacion INT -- ID de la versión a consultar
)
BEGIN
    /* Variables de Entorno */
    DECLARE v_Id_Padre_Capacitacion INT;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN Y DESCUBRIMIENTO (FAIL FAST)
       ============================================================================================ */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: ID de capacitación inválido.';
    END IF;

    /* Descubrir al Padre */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* Validar Existencia */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: La capacitación no existe.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: RESULTSET 1 (HEADER - DATOS DEL CURSO)
       Aquí es donde aplicamos la lógica de "Doble Auditoría" (Creador Original vs Editor Actual)
       ============================================================================================ */
    SELECT 
        /* --- IDENTIDAD --- */
        `VC`.`Id_Capacitacion`,
        `VC`.`Id_Detalle_de_Capacitacion`,
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Tipo_Instruccion`            AS `Tipo_Capacitacion`,
        `VC`.`Duracion_Horas`              AS `Duracion`,

        /* --- CONFIGURACIÓN (IDs para el Formulario) --- */
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`,
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,
        
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* --- ESTATUS --- */
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Útil para colores en Frontend

        /* --- DATOS OPERATIVOS --- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Observaciones`               AS `Bitacora_Notas`,
        
        /* --- METAS --- */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Reales`,

        /* --- BANDERAS DE ESTADO CRUDAS --- */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,  -- 1=Vivo, 0=Archivado (Padre)
        `DC`.`Activo`                      AS `Estatus_Del_Detalle`,   -- 1=Vigente, 0=Histórico (Hijo)

        /* =================================================================================
           AUDITORÍA FORENSE DIFERENCIADA (ORIGEN VS VERSIÓN ACTUAL)
           ================================================================================= */
        
        /* 1. EL ORIGEN (Padre - Tabla Capacitaciones) */
        /* ¿Cuándo nació el folio CAP-202X? */
        `Cap`.`created_at`                 AS `Fecha_Creacion_Original`,
        
        /* ¿Quién creó el folio? (Join Manual hacia el creador del Padre) */
        CONCAT(IFNULL(`IP_Creator`.`Nombre`,''), ' ', IFNULL(`IP_Creator`.`Apellido_Paterno`,'')) AS `Creado_Originalmente_Por`,

        /* 2. LA VERSIÓN ACTUAL (Hijo - Tabla DatosCapacitaciones) */
        /* ¿Cuándo se hizo esta modificación específica? */
        `DC`.`created_at`                  AS `Fecha_Ultima_Modificacion`, -- Ojo: En tu lógica de INSERT, el created_at del hijo es la fecha de modificación
        
        /* ¿Quién hizo esta modificación? (Join hacia el creador del Hijo) */
        CONCAT(IFNULL(`IP_Editor`.`Nombre`,''), ' ', IFNULL(`IP_Editor`.`Apellido_Paterno`,'')) AS `Ultima_Actualizacion_Por`

    FROM `Picade`.`DatosCapacitaciones` `DC`
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    INNER JOIN `Picade`.`Capacitaciones` `Cap`      ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN A: Creador de la Versión/Edición (DatosCapacitaciones) */
    LEFT JOIN `Picade`.`Usuarios` `U_Editor`        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Editor`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Editor`  ON `U_Editor`.`Fk_Id_InfoPersonal` = `IP_Editor`.`Id_InfoPersonal`

    /* JOIN B: Creador Original del Expediente (Capacitaciones) */
    /* Aquí conectamos con la columna Fk_Id_Usuario_Cap_Created_by que definiste en tu CREATE TABLE */
    LEFT JOIN `Picade`.`Usuarios` `U_Creator`       ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Creator`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Creator` ON `U_Creator`.`Fk_Id_InfoPersonal` = `IP_Creator`.`Id_InfoPersonal`
    
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ============================================================================================
       BLOQUE 3: RESULTSET 2 (BODY - LISTA NOMINAL)
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
       BLOQUE 4: RESULTSET 3 (FOOTER - HISTORIAL)
       ============================================================================================ */
    SELECT 
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`,
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC`
    /* Join para saber quién creó cada versión histórica */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U`             ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP`       ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`
    
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;