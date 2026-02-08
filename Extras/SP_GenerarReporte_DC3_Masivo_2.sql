
/* ======================================================================================================
   PROCEDIMEINIENTO: SP_GenerarReporte_DC3_Masivo
   ======================================================================================================
   IDENTIFICADOR:  SP_GenerarReporte_DC3_Masivo
   MÓDULO:         EMISIÓN DOCUMENTAL Y CERTIFICACIÓN LABORAL (DC-3 / STPS)
   
   1. DESCRIPCIÓN FUNCIONAL:
   -------------------------
   Este procedimiento actúa como el núcleo de lógica de negocios para la extracción de evidencia académica.
   Su función primaria es la discriminación y filtrado de registros de participación para identificar
   inequívocamente qué individuos son sujetos de certificación (DC-3) y quiénes de reconocimiento
   (Constancia de Participación), basándose en reglas de integridad de datos y estados de ciclo de vida.

   2. ARQUITECTURA DE INTEGRIDAD (FORENSIC LAYERS):
   -----------------------------------------------
   A. INTEGRIDAD PARAMÉTRICA: Verifica la existencia y validez de las llaves foráneas de entrada.
   B. INTEGRIDAD DE ESTADO: Valida que el contenedor (Curso) se encuentre en un estado inmutable (Finalizado).
   C. INTEGRIDAD DE DATOS (NULL CHECK): Aplica un "Hard Filter" sobre evidencias numéricas obligatorias.
   D. INTEGRIDAD SEMÁNTICA: Mapea IDs de estatus a nombres de catálogo para consumo humano en el Frontend.

   3. CONTRATO DE SALIDA (DATASETS):
   ---------------------------------
   - DATASET 1 (ALUMNOS): Estructura plana optimizada para motores de renderizado de PDF (DomPDF/Snappy).
   - DATASET 2 (AUDITORÍA): Métricas de control para retroalimentación al Coordinador sobre el éxito del lote.
   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_GenerarReporte_DC3_Masivo`$$

CREATE PROCEDURE `SP_GenerarReporte_DC3_Masivo`(
    IN _Id_Usuario_Ejecutor INT,      /* FK: Identificador del usuario que dispara la acción (Trazabilidad). */
    IN _Id_Detalle_Capacitacion INT   /* FK: Identificador único de la instancia operativa del curso (DatosCapacitaciones). */
)
ProcMasivo: BEGIN

    /* -----------------------------------------------------------------------------------
       SECCIÓN 1: DECLARACIÓN DE VARIABLES DE CONTROL Y AUDITORÍA
       Se instancian variables locales para el almacenamiento temporal de metadatos de estado.
       ----------------------------------------------------------------------------------- */
    DECLARE v_Id_Estatus_Curso INT;             -- Almacena el ID del estatus actual del curso.
    DECLARE v_Nombre_Estatus_Curso VARCHAR(100); -- Almacena la etiqueta textual para mensajes de error amigables.

    /* -----------------------------------------------------------------------------------
       SECCIÓN 2: BLOQUE DE VALIDACIÓN DE INTEGRIDAD FORENSE (VAL-0)
       Este bloque previene ejecuciones con parámetros nulos o fuera de rango lógico.
       ----------------------------------------------------------------------------------- */
    
    -- [VAL-0.1]: Verificación de Identidad del Ejecutor. 
    -- Previene llamadas anónimas que comprometan la trazabilidad de la auditoría.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio para la trazabilidad.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo; -- Aborto de ejecución por falta de identidad.
    END IF;

    -- [VAL-0.2]: Verificación del Recurso Objetivo.
    -- Garantiza que el puntero al curso sea una referencia válida antes de realizar JOINS pesados.
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio para localizar el recurso.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo; -- Aborto de ejecución por referencia nula.
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 3: COMPROBACIÓN DE CICLO DE VIDA DEL CURSO (VAL-1)
       Determina si el recurso se encuentra en una fase operativa que permita la emisión legal.
       ----------------------------------------------------------------------------------- */
    
    -- Extracción de metadatos de estatus mediante el cruce de la tabla transaccional y catálogo.
    SELECT 
        DC.`Fk_Id_CatEstCap`,
        CAT.`Nombre`
    INTO 
        v_Id_Estatus_Curso,
        v_Nombre_Estatus_Curso
    FROM `Picade`.`datoscapacitaciones` DC
    INNER JOIN `Picade`.`cat_estatus_capacitacion` CAT 
        ON DC.`Fk_Id_CatEstCap` = CAT.`Id_CatEstCap`
    WHERE DC.`Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    -- [VAL-1.1]: Verificación de Existencia Física.
    -- Si el SELECT anterior no arroja resultados, el ID proporcionado es un "Dead Link".
    IF v_Id_Estatus_Curso IS NULL THEN
        SELECT 
            'ERROR NO ENCONTRADO [404]: El curso solicitado no existe en la base de datos.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    -- [VAL-1.2]: Regla de Negocio de Inmutabilidad.
    -- Bloqueo de emisión si el curso no es ID 4 (Finalizado) o ID 10 (Archivado).
    -- Previene la generación de certificados en cursos que aún pueden sufrir cambios de nota.
    IF v_Id_Estatus_Curso NOT IN (4, 10) THEN
        SELECT 
            CONCAT('CONFLICTO [409]: El curso está en estatus "', UPPER(v_Nombre_Estatus_Curso), '". La emisión masiva solo es válida para estados de cierre (FINALIZADO/ARCHIVADO).') AS Mensaje, 
            'ERROR_DE_ESTATUS' AS Accion, 
            NULL AS Id_Registro_Participante;
        LEAVE ProcMasivo;
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 4: EXTRACCIÓN DE DATASET PRIMARIO (DATA-CORE)
       Este query consolida la información académica y biográfica del participante.
       Aplica JOINS optimizados hacia vistas y tablas de identidad personal.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'PROCESO_EXITOSO' AS Mensaje, -- Flag de éxito para el controlador de Laravel.
        'GENERAR_PDF'     AS Accion,  -- Comando semántico para disparar el generador de PDF.

        -- [BIOGRAFÍA DEL ALUMNO]: Estructura requerida por formatos legales.
        `VGP`.`Id_Registro_Participante` AS `Id_Interno`,
        `VGP`.`Ficha_Participante`       AS `Ficha_Empleado`,
        -- Concatenación bajo estándar forense: Apellido Paterno + Apellido Materno + Nombres.
        CONCAT(`VGP`.`Ap_Paterno_Participante`, ' ', `VGP`.`Ap_Materno_Participante`, ' ', `VGP`.`Nombre_Pila_Participante`) AS `Nombre_Completo_Alumno`,
        IFNULL(`Puesto`.`Nombre`, 'SIN PUESTO REGISTRADO') AS `Puesto_Laboral`,
        
        -- [EVIDENCIA ACADÉMICA]: Datos crudos extraídos de la relación Capacitaciones_Participantes.
        `CP`.`PorcentajeAsistencia` AS `Asistencia_Numerica`,
        `CP`.`Calificacion`         AS `Evaluacion_Numerica`,

        -- [ESTATUS SEMÁNTICO]: Resolución de IDs a etiquetas de catálogo para validez legal en el texto del PDF.
        `CatEst`.`Nombre`      AS `Nombre_Estatus`, -- Ej: ACREDITADO / NO ACREDITADO.
        `CatEst`.`Descripcion` AS `Descripcion_Estatus`,          -- Explicación extendida del resultado.

        -- [CONTEXTO ACADÉMICO]: Datos del curso para el encabezado del documento.
        `VGP`.`Folio_Curso`        AS `Folio_Sistema`,
        `VGP`.`Tema_Curso`         AS `Nombre_Tema`,
        `VGP`.`Fecha_Inicio`       AS `Periodo_Inicio`,
        `VGP`.`Fecha_Fin`          AS `Periodo_Fin`,
        `VGP`.`Duracion_Horas`     AS `Carga_Horaria`,
        `VGP`.`Instructor_Asignado` AS `Nombre_Instructor`

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    -- Unión con tabla de hechos para acceso a IDs de estatus y valores numéricos crudos.
    INNER JOIN `Picade`.`capacitaciones_participantes` `CP` 
        ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    -- Cruce con tabla maestra de usuarios para vinculación de perfiles.
    INNER JOIN `Picade`.`usuarios` `U` 
        ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    -- Acceso a información personal para extracción de datos biográficos (CURP/RFC/Puesto).
    INNER JOIN `Picade`.`info_personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
    -- Resolución de puesto mediante catálogo (LEFT JOIN para no excluir si el perfil es incompleto).
    LEFT JOIN `Picade`.`cat_puestos_trabajo` `Puesto` 
        ON `IP`.`Fk_Id_CatPuesto` = `Puesto`.`Id_CatPuesto`
    -- Resolución de estatus mediante catálogo para obtener nombres oficiales de acreditación.
    INNER JOIN `Picade`.`cat_estatus_participante` `CatEst` 
        ON `CP`.`Fk_Id_CatEstPart` = `CatEst`.`Id_CatEstPart`

    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
      -- [FILTRO DE SELECCIÓN]: Solo se incluyen estados terminales de acreditación (3) o no acreditación (4).
      -- Esto excluye automáticamente estados como 'Inscrito' (1) o 'Baja' (5).
      AND `CP`.`Fk_Id_CatEstPart` IN (3, 4)
      -- [CANDADO DE INTEGRIDAD NUMÉRICA]: Si el instructor no capturó evidencia, el registro se omite para evitar PDFs vacíos.
      AND `CP`.`Calificacion` IS NOT NULL 
      AND `CP`.`PorcentajeAsistencia` IS NOT NULL
      
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC; -- Ordenamiento alfabético estándar para impresión masiva.

    /* -----------------------------------------------------------------------------------
       SECCIÓN 5: DATASET DE AUDITORÍA Y CONTROL (METADATA)
       Este bloque provee la estadística necesaria para el Dashboard de confirmación.
       Permite al usuario identificar huecos de información en el lote solicitado.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_EJECUCION_FORENSE' AS Mensaje,
        -- Conteo total de individuos ligados a la capacitación.
        COUNT(*) AS `Poblacion_Total`,

        -- Conteo de éxito: Registros que cumplieron todos los filtros de la Sección 4.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND `CP`.`Calificacion` IS NOT NULL 
                 AND `CP`.`PorcentajeAsistencia` IS NOT NULL 
            THEN 1 ELSE 0 
        END) AS `Certificados_Listos`,

        -- Conteo de Errores Críticos: Tienen estatus de finalización pero falta captura de evidencia.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (3, 4) 
                 AND (`CP`.`Calificacion` IS NULL OR `CP`.`PorcentajeAsistencia` IS NULL)
            THEN 1 ELSE 0 
        END) AS `Alertas_Datos_Incompletos`,

        -- Conteo de Omisiones Administrativas: Alumnos que nunca fueron evaluados por el instructor.
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` IN (1, 2) 
            THEN 1 ELSE 0 
        END) AS `Alertas_Sin_Evaluacion`,
        
        -- Conteo de Bajas: Registros omitidos por retiro oficial del curso (Flujo normal).
        SUM(CASE 
            WHEN `CP`.`Fk_Id_CatEstPart` = 5 
            THEN 1 ELSE 0 
        END) AS `Registros_Baja_Omitidos`

    FROM `Picade`.`capacitaciones_participantes` `CP`
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