/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_EditarParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   
   - Nombre Oficial       : SP_EditarParticipanteCapacitacion
   - Sistema			  : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria			  : Registro de Calificaciones, Asistencia y Estatus de Resultados
   - Alias Operativo      : "El Calificador" / "The Result Grader"
   - Clasificación        : Transacción de Asentamiento de Resultados (Result Settlement Transaction)
   - Patrón de Diseño     : Hybrid Automatic-Manual State Machine with Data Immutability Check
   - Nivel de Aislamiento : REPEATABLE READ
   - Complejidad          : Media-Alta (Lógica de determinación de estatus por puntaje)

   II. PROPÓSITO Y VERSATILIDAD (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es la herramienta definitiva para el Coordinador. Su diseño permite:
   1. REGISTRO INICIAL: Asentar asistencia y nota por primera vez.
   2. EDICIÓN POR ERROR: Corregir un dedo mal puesto en una calificación o asistencia.
   3. OVERRIDE MANUAL: Forzar estatus independientemente de la nota (ej. Aprobación por decreto).
   4. TRAZABILIDAD TOTAL: Obliga a justificar el "Por Qué" del dato, vital para auditorías externas.

   III. JERARQUÍA DE LÓGICA DE NEGOCIO (LOGIC HIERARCHY)
   ----------------------------------------------------------------------------------------------------------
   El sistema evalúa las entradas en este orden de prioridad:
   - PRIORIDAD 1 (Override): Si _Id_Estatus_Resultado tiene valor, se ignora el cálculo y se obedece al Admin.
   - PRIORIDAD 2 (Matemática): Si hay Nota, se calcula Aprobado (>=70) o Reprobado (<70).
   - PRIORIDAD 3 (Presencia): Si solo hay Asistencia, el estatus se marca como "Asistió".
   - PRIORIDAD 4 (Persistencia): Si un campo es NULL, se mantiene el valor que ya existía en la BD.

   ========================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_EditarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_EditarParticipanteCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario_Ejecutor INT,           -- ID del Admin/Instructor que realiza la acción.
    IN _Id_Registro_Participante INT,      -- PK de la inscripción (Id_CapPart).
    IN _Calificacion DECIMAL(5,2),         -- Nueva nota (0-100). NULL para no modificar.
    IN _Porcentaje_Asistencia DECIMAL(5,2),-- Nuevo % asistencia (0-100). NULL para no modificar.
    IN _Id_Estatus_Resultado INT,          -- Cambio manual de estatus. NULL para cálculo automático.
    IN _Justificacion_Cualitativa VARCHAR(250) -- Explicación del cambio o motivo de la nota.
)
ProcUpdatResulPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (DATA SNAPSHOT)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Variables de integridad
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    
    -- Variables de estado previo (Para comparación y auditoría)
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Calificacion_Previa DECIMAL(5,2);
    DECLARE v_Asistencia_Previa DECIMAL(5,2);
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    
    -- Variables de cálculo
    DECLARE v_Nuevo_Estatus_Calculado INT DEFAULT 0;
    DECLARE v_Audit_Trail_Final TEXT;
    
    -- Constantes de Negocio PICADE
    DECLARE c_EST_ASISTIO INT DEFAULT 2;       -- Alumno completó asistencia pero no se evaluó.
    DECLARE c_EST_APROBADO INT DEFAULT 3;      -- Alumno superó el umbral de 70.
    DECLARE c_EST_REPROBADO INT DEFAULT 4;     -- Alumno no alcanzó el umbral de 70.
    DECLARE c_EST_BAJA INT DEFAULT 5;          -- Participante inactivo (Ineditable).
    DECLARE c_UMBRAL_APROBACION DECIMAL(5,2) DEFAULT 70.00;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: SEGURIDAD Y ATOMICIDAD (ACID)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'ERROR TÉCNICO [500]: Fallo crítico al intentar asentar resultados o editar registro.' AS Mensaje, 'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN FORENSE (FAIL-FAST)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    -- 0.1 Validación de IDs
    IF _Id_Usuario_Ejecutor <= 0 OR _Id_Registro_Participante <= 0 THEN 
        SELECT 'ERROR DE ENTRADA [400]: Los identificadores son obligatorios y deben ser positivos.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- 0.2 Validación de Rangos Matemáticos
    IF (_Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100)) OR 
       (_Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100)) THEN
        SELECT 'ERROR DE RANGO [400]: Las notas y asistencias deben estar entre 0.00 y 100.00.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    -- 0.3 Validación de Justificación: Exigencia de trazabilidad del estándar Platinum.
    IF _Justificacion_Cualitativa IS NULL OR TRIM(_Justificacion_Cualitativa) = '' THEN
        SELECT 'ERROR DE AUDITORÍA [400]: Es obligatorio justificar el asentamiento o cambio de resultados.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE SNAPSHOT ACADÉMICO (READ BEFORE WRITE)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Verificación de Identidad del Ejecutor
    SELECT COUNT(*) INTO v_Ejecutor_Existe FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Ejecutor AND `Activo` = 1;
    IF v_Ejecutor_Existe = 0 THEN 
        SELECT 'ERROR DE PERMISOS [403]: El usuario ejecutor no existe o no tiene cuenta activa.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- 1.2 Hidratación de Snapshot (Capturamos los datos actuales antes de que desaparezcan)
    SELECT 
        COUNT(*), `CP`.`Fk_Id_CatEstPart`, `CP`.`Calificacion`, `CP`.`PorcentajeAsistencia`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), `C`.`Numero_Capacitacion`
    INTO 
        v_Registro_Existe, v_Estatus_Actual, v_Calificacion_Previa, v_Asistencia_Previa,
        v_Nombre_Alumno, v_Folio_Curso
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- 1.3 Validación de Existencia de Registro
    IF v_Registro_Existe = 0 THEN 
        SELECT 'ERROR DE INTEGRIDAD [404]: No se encontró el registro de asistencia del participante.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- 1.4 Protección de Bajas: Si está en BAJA (5), el registro está congelado.
    IF v_Estatus_Actual = c_EST_BAJA THEN
        SELECT CONCAT('ERROR DE NEGOCIO [409]: Imposible calificar a "', v_Nombre_Alumno, '" porque está dado de BAJA administrativa.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: MÁQUINA DE ESTADOS Y CÁLCULO DE AUDITORÍA (BUSINESS LOGIC)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    

    -- [2.1] Determinación de Nuevo Estatus (Jerarquía de Prioridades)
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- Prioridad 1: Manual (Admin manda)
        SET v_Nuevo_Estatus_Calculado = _Id_Estatus_Resultado;
    ELSEIF _Calificacion IS NOT NULL THEN
        -- Prioridad 2: Cálculo Matemático
        IF _Calificacion >= c_UMBRAL_APROBACION THEN SET v_Nuevo_Estatus_Calculado = c_EST_APROBADO;
        ELSE SET v_Nuevo_Estatus_Calculado = c_EST_REPROBADO; END IF;
    ELSEIF _Porcentaje_Asistencia IS NOT NULL AND v_Estatus_Actual = 1 THEN
        -- Prioridad 3: Registro de Asistencia (Mueve de Inscrito a Asistió)
        SET v_Nuevo_Estatus_Calculado = c_EST_ASISTIO;
    ELSE
        -- Prioridad 4: Mantener estatus previo
        SET v_Nuevo_Estatus_Calculado = v_Estatus_Actual;
    END IF;

    -- [2.2] Construcción de Nota Forense Acumulativa
    -- Detallamos qué se cambió para que el auditor no tenga que adivinar.
    SET v_Audit_Trail_Final = CONCAT(
        'EDIT_RES [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ',
        'NUEVA_NOTA: ', COALESCE(_Calificacion, v_Calificacion_Previa, '0.00'), 
        ' | NUEVA_ASIST: ', COALESCE(_Porcentaje_Asistencia, v_Asistencia_Previa, '0.00'), '%',
        ' | MOTIVO: ', _Justificacion_Cualitativa
    );

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: PERSISTENCIA TRANSACCIONAL (DATA SETTLEMENT)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        -- Actualizamos la fila aplicando COALESCE para permitir actualizaciones parciales.
        UPDATE `Capacitaciones_Participantes`
        SET 
            `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
            `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
            `Fk_Id_CatEstPart` = v_Nuevo_Estatus_Calculado,
            -- Inyectamos el motivo en la columna Justificacion
            `Justificacion` = v_Audit_Trail_Final,
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA DINÁMICA (UX FEEDBACK)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('DATOS ACTUALIZADOS: Alumno "', v_Nombre_Alumno, '" en el curso "', v_Folio_Curso, '".') AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;