DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_GenerarReporte_DC3_Masivo`$$

CREATE PROCEDURE `SP_GenerarReporte_DC3_Masivo`(
    IN _Id_Usuario_Ejecutor INT,      -- Quién dio el clic
    IN _Id_Detalle_Capacitacion INT   -- Qué curso se va a imprimir
)
ProcMasivo: BEGIN

    /* -------------------------------------------------------------------------
       VARIABLES
       ------------------------------------------------------------------------- */
    DECLARE v_Id_Estatus_Curso INT;
    DECLARE v_Nombre_Estatus_Curso VARCHAR(100);

    /* -------------------------------------------------------------------------
       VALIDACIÓN 0.1: INTEGRIDAD DE ENTRADA (Tu formato estándar)
       ------------------------------------------------------------------------- */
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    /* -------------------------------------------------------------------------
       VALIDACIÓN 0.2: ESTATUS DEL CURSO (Lógica de Negocio)
       ------------------------------------------------------------------------- */
    SELECT 
        DC.`Fk_Id_CatEstCap`,
        CAT.`Nombre`
    INTO 
        v_Id_Estatus_Curso,
        v_Nombre_Estatus_Curso
    FROM `Picade`.`DatosCapacitaciones` DC
    INNER JOIN `Picade`.`Cat_Estatus_Capacitacion` CAT 
        ON DC.`Fk_Id_CatEstCap` = CAT.`Id_CatEstCap`
    WHERE DC.`Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    -- A) Si no existe el curso
    IF v_Id_Estatus_Curso IS NULL THEN
        SELECT 'ERROR NO ENCONTRADO [404]: El curso solicitado no existe.' AS Mensaje, 
               'RECURSO_NO_ENCONTRADO' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    -- B) Si el curso NO está terminado (4=Finalizado, 10=Archivado)
    IF v_Id_Estatus_Curso NOT IN (4, 10) THEN
        SELECT CONCAT('CONFLICTO [409]: El curso está en estatus "', UPPER(v_Nombre_Estatus_Curso), '". Solo se procesan cursos FINALIZADOS o ARCHIVADOS.') AS Mensaje, 
               'ERROR_DE_ESTATUS' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    /* =========================================================================
       SI TODO ESTÁ BIEN, RETORNAMOS LA DATA REAL
       ========================================================================= */

    /* -------------------------------------------------------------------------
       TABLA 1: LISTA DE ALUMNOS (PARA EL PDF)
       ------------------------------------------------------------------------- */
    SELECT 
        'PROCESO_EXITOSO' AS Mensaje,
        'GENERAR_PDF'     AS Accion,

        -- Datos Alumno
        `VGP`.`Id_Registro_Participante`,
        `VGP`.`Ficha_Participante`,
        CONCAT(`VGP`.`Ap_Paterno_Participante`, ' ', `VGP`.`Ap_Materno_Participante`, ' ', `VGP`.`Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        -- IFNULL(`IP`.`CURP`, '') AS `CURP`,
        IFNULL(`Puesto`.`Nombre`, '') AS `Puesto_Trabajo`,
        
        -- Resultados Numéricos
        `CP`.`Calificacion` AS `Nota_Final`,
        `CP`.`PorcentajeAsistencia` AS `Asistencia_Final`,

        -- [CAMBIO SOLICITADO]: Usamos el Nombre Real del Catálogo
        -- Laravel leerá esto: "APROBADO" o "NO ACREDITADO"
        `CatEst`.`Nombre`      AS `Estatus_Nombre`,      -- Ej: "APROBADO"
        `CatEst`.`Descripcion` AS `Estatus_Descripcion`, -- Ej: "El alumno cumplió satisfactoriamente..."
        -- `CatEst`.`Codigo`      AS `Estatus_Codigo`,      -- Ej: "APR" (Útil para lógica interna si existe)

        -- Datos Curso (Cabecera del PDF)
        `VGP`.`Folio_Curso`,
        `VGP`.`Tema_Curso`,
        `VGP`.`Fecha_Inicio`,
        `VGP`.`Fecha_Fin`,
        `VGP`.`Duracion_Horas`,
        `VGP`.`Instructor_Asignado`

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    INNER JOIN `Picade`.`Capacitaciones_Participantes` `CP` ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    INNER JOIN `Picade`.`Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Picade`.`Info_Personal` `IP` ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
    LEFT JOIN `Picade`.`Cat_Puestos_Trabajo` `Puesto` ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`
    
    -- [NUEVO JOIN]: Para traer el nombre del estatus del participante
    INNER JOIN `Picade`.`Cat_Estatus_Participante` `CatEst` ON `CP`.`Fk_Id_CatEstPart` = `CatEst`.`Id_CatEstPart`

    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
      -- Solo traemos los que ya tienen veredicto final (3=Acreditado, 4=No Acreditado)
      AND `CP`.`Fk_Id_CatEstPart` IN (3, 4)
      -- Integridad Obligatoria
      AND `CP`.`Calificacion` IS NOT NULL 
      AND `CP`.`PorcentajeAsistencia` IS NOT NULL
      
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC;

    /* -------------------------------------------------------------------------
       TABLA 2: RESUMEN DE ALERTAS (PARA EL AVISO EN PANTALLA)
       Esto le dice al usuario "Ojo, te faltaron X alumnos"
       ------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_PROCESAMIENTO' AS Mensaje,
        
        -- Total real en lista
        COUNT(*) AS `Total_Inscritos`,

        -- Cuántos PDFs se van a generar (Éxito)
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND `CP`.`Calificacion` IS NOT NULL 
                 AND `CP`.`PorcentajeAsistencia` IS NOT NULL 
            THEN 1 ELSE 0 
        END) AS `DC3_Generados`,

        -- [ALERTA CRÍTICA]: Tienen estatus final, pero les faltan datos numéricos
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND (`CP`.`Calificacion` IS NULL OR `CP`.`PorcentajeAsistencia` IS NULL)
            THEN 1 ELSE 0 
        END) AS `Error_Datos_Incompletos`,

        -- [ALERTA DE PROCESO]: Se quedaron como "Asistió" o "Inscrito" (Olvido del Instructor)
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (1, 2) 
            THEN 1 ELSE 0 
        END) AS `Error_Sin_Evaluar`,
        
                -- [ALERTA DE PROCESO]: Se quedaron como "Asistió" o "Inscrito" (Olvido del Instructor)
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (5) 
            THEN 1 ELSE 0 
        END) AS `Error_Omitidos_Baja`

    FROM `Picade`.`Capacitaciones_Participantes` `CP`
    WHERE `CP`.`Fk_Id_DatosCap` = _Id_Detalle_Capacitacion;

END$$

DELIMITER ;

-- Generar DC-3 para el Curso 1 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C01_Ver);
-- Generar DC-3 para el Curso 2 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C02_Ver);
-- Generar DC-3 para el Curso 3 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C03_Ver);
-- Generar DC-3 para el Curso 4 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C04_Ver);
-- Generar DC-3 para el Curso 5 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C05_Ver);
-- Generar DC-3 para el Curso 6 de la batería
CALL SP_GenerarReporte_DC3_Masivo(@AdminEjecutor, @C06_Ver);

DROP PROCEDURE IF EXISTS `SP_GenerarReporte_DC3_Masivo`;