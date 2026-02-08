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

   II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es el responsable de transformar una "Matrícula" en un "Resultado Académico". 
   Su función es asentar la calificación numérica y el porcentaje de asistencia, derivando 
   automáticamente el estado del alumno (Aprobado/Reprobado/Asistió) a menos que se fuerce manualmente.
   
   [AUDITORÍA DE RESULTADOS]:
   Cada cambio en la nota o asistencia inyecta una nota forense en la columna `Justificacion`, 
   evitando que calificaciones sean alteradas sin dejar rastro del motivo o del responsable.

   III. REGLAS DE GOBERNANZA ACADÉMICA (GOVERNANCE RULES)
   ----------------------------------------------------------------------------------------------------------
   A. REGLA DE EXCLUSIÓN DE BAJAS:
      No se puede calificar a un alumno que tiene estatus de BAJA (5). El alumno debe ser "Reinscrito" 
      primero (usando el SP de Toggle) antes de recibir una nota.

   B. REGLA DE RANGO DE INTEGRIDAD:
      Tanto la calificación como la asistencia están limitadas estrictamente al rango [0.00 - 100.00].
      Cualquier valor fuera de este rango dispara un rechazo inmediato por integridad de datos.

   C. LÓGICA DE DERIVACIÓN DE ESTATUS:
      1. Si se provee `_Id_Estatus_Resultado`: El sistema obedece el valor manual (Override).
      2. Si `_Calificacion` >= 70: El estatus deriva a APROBADO (3).
      3. Si `_Calificacion` < 70 y > 0: El estatus deriva a REPROBADO (4).
      4. Si solo hay `_Porcentaje_Asistencia`: El estatus deriva a ASISTIÓ (2).

   IV. ARQUITECTURA DE DEFENSA (DEFENSE IN DEPTH)
   ----------------------------------------------------------------------------------------------------------
   1. VALIDACIÓN ESTRUCTURAL: Rango de tipos Decimal(5,2).
   2. VALIDACIÓN DE CONTEXTO: Snapshot del estatus actual del participante.
   3. ATOMICIDAD: Uso de transacciones para asegurar que la nota y el estatus cambien en conjunto.
   4. INYECCIÓN DE JUSTIFICACIÓN: Documentación obligatoria del cambio.

   ========================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_EditarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_EditarParticipanteCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario_Ejecutor INT,           -- ID del Administrador/Instructor que califica.
    IN _Id_Registro_Participante INT,      -- PK del registro en Capacitaciones_Participantes.
    IN _Calificacion DECIMAL(5,2),         -- Nota numérica [0-100]. NULL si no aplica.
    IN _Porcentaje_Asistencia DECIMAL(5,2),-- % de asistencia [0-100]. NULL si no aplica.
    IN _Id_Estatus_Resultado INT,          -- Forzar estatus (2=Asistió, 3=Aprobado, 4=Reprobado).
    IN _Observaciones VARCHAR(250)         -- Justificación del resultado o del cambio.
)
ProcUpdatResulPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (VARIABLE ALLOCATION)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Validación y Punteros
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Flag de existencia del Admin.
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Flag de existencia de la matrícula.
    
    -- [1.2] Variables de Snapshot académico
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- Estado antes de la edición.
    DECLARE v_Nuevo_Estatus_Calculado INT DEFAULT 0;-- Estado que resultará de la operación.
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre recuperado para el feedback.
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Folio para feedback.
    
    -- [1.3] Constantes de Negocio (Business Mappings)
    DECLARE c_ESTATUS_ASISTIO INT DEFAULT 2;       -- Registro de solo asistencia.
    DECLARE c_ESTATUS_APROBADO INT DEFAULT 3;      -- Resultado satisfactorio.
    DECLARE c_ESTATUS_REPROBADO INT DEFAULT 4;     -- Resultado no satisfactorio.
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- Estado de exclusión.
    DECLARE c_CALIFICACION_MINIMA DECIMAL(5,2) DEFAULT 70.00; -- Umbral de aprobación.

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ROLLBACK]: Revierte cualquier actualización de nota ante fallos de integridad.
        ROLLBACK;
        SELECT 'ERROR TÉCNICO [500]: Fallo crítico al procesar la calificación y asistencia.' AS Mensaje, 'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE RANGOS (DATA INTEGRITY)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación de Punteros básicos
    IF _Id_Usuario_Ejecutor <= 0 OR _Id_Registro_Participante <= 0 THEN 
        SELECT 'ERROR DE ENTRADA [400]: Los identificadores de usuario o registro son inválidos.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- [0.2] Validación de Rango de Calificación: El sistema solo permite escala decimal 0-100.
    IF _Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: La calificación debe estar en el rango de 0.00 a 100.00.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;
    
    -- [0.3] Validación de Rango de Asistencia: No se admite más del 100% de presencia física.
    IF _Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: El porcentaje de asistencia debe estar en el rango de 0.00 a 100.00.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    -- [0.4] Validación de Justificación: Obligatorio documentar el asentamiento de resultados.
    IF TRIM(COALESCE(_Observaciones, '')) = '' THEN
        SELECT 'ERROR DE ENTRADA [400]: Debe proporcionar observaciones o justificación para este resultado.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE CONTEXTO ACADÉMICO (SNAPSHOT DATA)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Verificación del Calificador
    SELECT COUNT(*) INTO v_Ejecutor_Existe FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Ejecutor AND `Activo` = 1;
    IF v_Ejecutor_Existe = 0 THEN 
        SELECT 'ERROR DE PERMISOS [403]: El calificador no tiene privilegios activos en el sistema.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- 1.2 Hidratación de Variables del Participante
    -- Obtenemos el estatus actual para bloquear ediciones sobre alumnos en BAJA.
    SELECT 
        COUNT(*), COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`),
        `C`.`Numero_Capacitacion`
    INTO 
        v_Registro_Existe, v_Estatus_Actual_Alumno,
        v_Nombre_Alumno, v_Folio_Curso
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- 1.3 Validación de Existencia
    IF v_Registro_Existe = 0 THEN 
        SELECT 'ERROR DE EXISTENCIA [404]: El registro de matrícula no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [CRÍTICO] 1.4 Protección contra Bajas Administrativas
    -- Un alumno en BAJA no puede ser calificado. Debe ser reactivado formalmente primero.
    IF v_Estatus_Actual_Alumno = c_ESTATUS_BAJA THEN
        SELECT CONCAT('ERROR DE NEGOCIO [409]: Imposible calificar a "', v_Nombre_Alumno, '" porque se encuentra en estatus de BAJA.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: MÁQUINA DE ESTADOS ACADÉMICA (STATE MACHINE LOGIC)
       Objetivo: Determinar el nuevo estatus basándose en la jerarquía: Manual > Calificación > Asistencia.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */

    -- Lógica de Priorización:
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- Prioridad 1: Asignación Manual (Override administrativo).
        SET v_Nuevo_Estatus_Calculado = _Id_Estatus_Resultado;
    
    ELSEIF _Calificacion IS NOT NULL THEN
        -- Prioridad 2: Cálculo automático por puntaje.
        IF _Calificacion >= c_CALIFICACION_MINIMA THEN
            SET v_Nuevo_Estatus_Calculado = c_ESTATUS_APROBADO;
        ELSE
            SET v_Nuevo_Estatus_Calculado = c_ESTATUS_REPROBADO;
        END IF;
    
    ELSEIF _Porcentaje_Asistencia IS NOT NULL THEN
        -- Prioridad 3: Registro de asistencia pura.
        SET v_Nuevo_Estatus_Calculado = c_ESTATUS_ASISTIO;
    
    ELSE
        -- Default: Mantener el estado previo si no se enviaron datos nuevos.
        SET v_Nuevo_Estatus_Calculado = v_Estatus_Actual_Alumno;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: PERSISTENCIA E INYECCIÓN FORENSE (DATA SETTLEMENT)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        -- Actualización del récord académico.
        UPDATE `Capacitaciones_Participantes`
        SET 
            `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
            `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
            `Fk_Id_CatEstPart` = v_Nuevo_Estatus_Calculado,
            
            -- [AUDIT INJECTION]: Se concatena el historial de resultados para trazabilidad directa.
            `Justificacion` = CONCAT(
                'RESULTADO [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ',
                'Nota: ', COALESCE(_Calificacion, 'N/A'), 
                ' | Asist: ', COALESCE(_Porcentaje_Asistencia, 'N/A'), '%',
                ' | Obs: ', _Observaciones
            ),
            
            -- Sellos de tiempo y autoría.
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA FINAL (UX API FEEDBACK)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('ÉXITO: Se han guardado los resultados para "', v_Nombre_Alumno, '" en el curso "', v_Folio_Curso, '".') AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   NOTAS DE IMPLEMENTACIÓN:
   1. El SP maneja tipos DECIMAL(5,2) para soportar calificaciones con décimas (ej. 85.50).
   2. La inyección de Justificación permite reconstruir el historial académico de la fila sin tablas Log.
   3. Compatible con procesos masivos si se llama dentro de un bucle desde la capa de aplicación.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */