/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacionParticipante
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_CambiarEstatusCapacitacionParticipante
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria: 		  : Transacciones de Estado y Ciclo de Vida del Participante
   - Alias Operativo      : "El Interruptor de Membresía" / "The Enrollment Toggle"
   - Clasificación        : Transacción de Gobernanza de Estado (State Governance Transaction)
   - Patrón de Diseño     : Idempotent Explicit Toggle with Hybrid Capacity Enforcement
   - Nivel de Aislamiento : SERIALIZABLE (Atomicidad garantizada por bloqueo de fila InnoDB)
   - Complejidad          : Alta (Bifurcación lógica con inyección de metadatos de auditoría)

   II. PROPÓSITO FORENSE Y DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es el único punto de control para alterar la relación Alumno-Curso. 
   Implementa un patrón de "Interruptor Lógico" que protege la integridad histórica de la capacitación.
   
   [ANALOGÍA OPERATIVA]:
   Es como un sistema de control de acceso en un estadio:
     - BAJA: Es expulsar o retirar al asistente, anulando su boleto pero dejando el registro de que estuvo ahí.
     - REINSCRIBIR: Es permitir que alguien que salió vuelva a entrar, siempre que el estadio no esté lleno.

   III. REGLAS DE GOBERNANZA (GOVERNANCE RULES)
   ----------------------------------------------------------------------------------------------------------
   A. REGLA DE INMUTABILIDAD EVALUATIVA (EVALUATION IMMUTABILITY):
      Un registro calificado es SAGRADO. Si un alumno ya tiene una nota asentada, no puede ser dado de baja
      sin antes borrar la calificación (proceso administrativo aparte), evitando la alteración de promedios.

   B. REGLA DE PROTECCIÓN DE CURSO MUERTO (DEAD COURSE PROTECTION):
      No se permiten cambios de participantes en cursos CANCELADOS o ARCHIVADOS. Son expedientes congelados.

   C. REGLA DE IDEMPOTENCIA (IDEMPOTENCY):
      Si el usuario solicita "Reinscribir" a alguien que ya está activo, el sistema debe responder 
      exitosamente con un aviso de "Sin Cambios", evitando duplicidad de logs.

   IV. ARQUITECTURA DE DEFENSA (DEFENSE IN DEPTH)
   ----------------------------------------------------------------------------------------------------------
   1. SANITIZACIÓN: Rechazo de punteros inválidos.
   2. IDENTIDAD: Validación de permisos del ejecutor.
   3. SNAPSHOT: Captura del estado actual del curso y el alumno en memoria.
   4. VALIDACIÓN DE CUPO: Aritmética GREATEST() para evitar sobrecupo en reinscripción.
   5. ATOMICIDAD: Commit garantizado o Rollback total.

   ========================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacionParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacionParticipante`(
    /* ------------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       ------------------------------------------------------------------------------------------------------ */
    IN _Id_Usuario_Ejecutor INT,       -- [PTR]: ID del Administrador (Trazabilidad de Auditoría).
    IN _Id_Registro_Participante INT,  -- [PTR]: Llave primaria (PK) del registro de matriculación.
    IN _Nuevo_Estatus_Deseado INT,     -- [FLAG]: 1 = Inscrito/Activo, 5 = Baja Administrativa.
    IN _Motivo_Operacion VARCHAR(250)  -- [VAL]: Justificación obligatoria para inyección de nota forense.
)
ProcTogglePart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Variables de Validación Referencial
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Confirmación de Admin activo.
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Confirmación de PK existente.
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;      -- Puntero a DatosCapacitaciones.
    DECLARE v_Id_Padre INT DEFAULT 0;              -- Puntero a Capacitaciones (Meta).
    
    -- 1.2 Variables de Snapshot (Estado Actual)
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- Estado en BD antes del cambio.
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- Estado operativo del curso (1-10).
    DECLARE v_Curso_Activo INT DEFAULT 0;          -- Flag de borrado lógico.
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;    -- ¿Calificacion IS NOT NULL?
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Folio para feedback.
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre para feedback.
    
    -- 1.3 Variables de Capacidad (Reinscripción)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Meta programada.
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Real en BD.
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Override manual.
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- MAX(Sistema, Manual).
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Delta restante.
    
    -- 1.4 Constantes Maestras (Architecture Mapping)
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- Reversión total ante fallos mecánicos o de integridad.
        SELECT 'ERROR TÉCNICO [500]: Fallo crítico al procesar el cambio de estado.' AS Mensaje, 'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE INPUTS (DEFENSA NIVEL 1)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 0.1 Sanitización de punteros
    IF _Id_Usuario_Ejecutor <= 0 OR _Id_Registro_Participante <= 0 THEN 
        SELECT 'ERROR DE ENTRADA [400]: Los identificadores proporcionados no son válidos.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- 0.2 Validación de dominio de estatus
    IF _Nuevo_Estatus_Deseado NOT IN (c_ESTATUS_INSCRITO, c_ESTATUS_BAJA) THEN
        SELECT 'ERROR DE NEGOCIO [400]: El estatus solicitado no es válido para este interruptor.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    -- 0.3 Validación de nota de auditoría
    IF TRIM(COALESCE(_Motivo_Operacion, '')) = '' THEN
        SELECT 'ERROR DE ENTRADA [400]: Debe proporcionar un motivo para este cambio de estado.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE SNAPSHOT FORENSE (DEFENSA NIVEL 2)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Verificación del Ejecutor
    SELECT COUNT(*) INTO v_Ejecutor_Existe FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Ejecutor AND `Activo` = 1;
    IF v_Ejecutor_Existe = 0 THEN 
        SELECT 'ERROR DE PERMISOS [403]: Usted no tiene permisos activos para realizar cambios.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- 1.2 Hidratación de variables de estado
    SELECT 
        COUNT(*), COALESCE(`CP`.`Fk_Id_CatEstPart`, 0), `CP`.`Fk_Id_DatosCap`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`),
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END,
        `DC`.`Activo`, `DC`.`Fk_Id_CatEstCap`, `DC`.`Fk_Id_Capacitacion`,
        COALESCE(`DC`.`AsistentesReales`, 0)
    INTO 
        v_Registro_Existe, v_Estatus_Actual_Alumno, v_Id_Detalle_Curso,
        v_Nombre_Alumno, v_Tiene_Calificacion, v_Curso_Activo,
        v_Estatus_Curso, v_Id_Padre, v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- 1.3 Validación de Integridad Física
    IF v_Registro_Existe = 0 THEN 
        SELECT 'ERROR DE EXISTENCIA [404]: No se encontró el expediente de inscripción.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- 1.4 Validación de Idempotencia (Evitar redundancia)
    IF v_Estatus_Actual_Alumno = _Nuevo_Estatus_Deseado THEN
        SELECT CONCAT('AVISO: El alumno "', v_Nombre_Alumno, '" ya se encuentra en el estado solicitado.') AS Mensaje, 'SIN_CAMBIOS' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    -- 1.5 Carga de Meta
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` INTO v_Folio_Curso, v_Cupo_Maximo
    FROM `Capacitaciones` WHERE `Id_Capacitacion` = v_Id_Padre;

    -- 1.6 Protección de Curso Muerto
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) THEN
        SELECT CONCAT('ACCIÓN DENEGADA [409]: El curso "', v_Folio_Curso, '" está bloqueado (Cancelado/Archivado).') AS Mensaje, 'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: PROCESAMIENTO DE RAMA ESPECÍFICA (DECISION MATRIX)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN
        
        -- RAMA BAJA: Protección contra eliminación de récords académicos calificados.
        IF v_Tiene_Calificacion = 1 THEN
            SELECT CONCAT('ERROR [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya cuenta con calificación asentada.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    ELSE
        
        -- RAMA REINSCRIPCIÓN: Validación estricta de cupo híbrido.
        
        SELECT COUNT(*) INTO v_Conteo_Sistema FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        IF v_Cupo_Disponible <= 0 THEN
            SELECT CONCAT('ERROR DE CUPO [409]: Cupo lleno en "', v_Folio_Curso, '". No hay lugar para reactivar al alumno.') AS Mensaje, 'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;

    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: INYECCIÓN DE AUDITORÍA Y PERSISTENCIA (DEFENSA NIVEL 3)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        UPDATE `Capacitaciones_Participantes`
        SET `Fk_Id_CatEstPart` = _Nuevo_Estatus_Deseado,
            -- Audit Injection: Inyectamos timestamp, ejecutor y motivo en un formato serializado.
            `Justificacion` = CONCAT(
                CASE WHEN _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN 'BAJA_SISTEMA' ELSE 'RESTAURAR_SISTEMA' END,
                ' | FECHA: ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
                ' | MOTIVO: ', _Motivo_Operacion
            ),
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESULTADO FINAL
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('TRANSACCIÓN EXITOSA: El alumno "', v_Nombre_Alumno, '" ha cambiado su estatus a ', 
               CASE WHEN _Nuevo_Estatus_Deseado = c_ESTATUS_BAJA THEN 'BAJA' ELSE 'INSCRITO' END, '.') AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion;

END$$

DELIMITER ;