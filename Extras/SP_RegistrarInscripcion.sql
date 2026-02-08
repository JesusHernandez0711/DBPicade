USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarInscripcion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es la puerta de entrada para poblar la tabla `Capacitaciones_Participantes`.
   
   [CASOS DE USO]:
   1. Auto-Servicio: Un participante se inscribe a sí mismo.
      -> Se envía con Estatus Inicial = 'PENDIENTE' (o el ID correspondiente).
   2. Gestión Administrativa: Un Admin inscribe a un usuario manualmente.
      -> Se envía con Estatus Inicial = 'INSCRITO' (Saltándose la aprobación).

   ----------------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] PREVENCIÓN DE DUPLICADOS (IDEMPOTENCIA):
      - Si el usuario ya está inscrito en esa capacitación, el sistema NO debe duplicar el registro
        ni lanzar un error fatal.
      - Acción: Devuelve un mensaje "Ya registrado" y retorna el ID existente.

   [RN-02] VALIDACIÓN DE VIGENCIA DEL CURSO (LIFECYCLE CHECK):
      - Regla: "No puedes subirte a un tren que ya partió".
      - Validación: Se verifica que la Capacitación (`DatosCapacitaciones`) esté ACTIVA.
      - Validación Profunda: Se verifica que el Estatus de la Capacitación NO sea Final 
        (ej: No permitir inscribirse a un curso "FINALIZADO" o "CANCELADO").

   [RN-03] INTEGRIDAD REFERENCIAL:
      - Verifica que existan el Usuario, la Capacitación y el Estatus solicitado.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE SALIDA
   ----------------------------------------------------------------------------------------------------
   Retorna: { Mensaje, Accion ('INSCRITO', 'REUSADO', 'ERROR'), Id_CapPart }.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarInscripcion`$$

CREATE PROCEDURE `SP_RegistrarInscripcion`(
    IN _Id_DatosCap     INT, -- ID de la Capacitación específica (Grupo/Horario)
    IN _Id_Usuario      INT, -- ID del Participante
    IN _Id_Estatus_Ini  INT  -- ID del Estatus inicial (ej: 1=Pendiente, 2=Inscrito)
)
THIS_PROC: BEGIN
    
    /* Variables de Estado */
    DECLARE v_Id_Existente INT DEFAULT NULL;
    DECLARE v_Estatus_Actual INT DEFAULT NULL;
    
    /* Variables para validar el curso */
    DECLARE v_Curso_Activo TINYINT DEFAULT NULL;
    DECLARE v_Es_Final     TINYINT DEFAULT NULL;
    DECLARE v_Folio_Curso  VARCHAR(50) DEFAULT NULL;

    /* Handler de Excepciones */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 1: VALIDACIONES FAIL-FAST
       ======================================================================================== */
    IF _Id_DatosCap IS NULL OR _Id_Usuario IS NULL OR _Id_Estatus_Ini IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Faltan parámetros obligatorios para la inscripción.';
    END IF;

    /* ========================================================================================
       BLOQUE 2: LÓGICA TRANSACCIONAL
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 2.1: VALIDAR ESTADO DEL CURSO (NO SUBIRSE AL TITANIC)
       Verificamos que el curso exista y que esté en una etapa que permita inscripciones.
       ---------------------------------------------------------------------------------------- */
    SELECT 
        DC.Activo, 
        EC.Es_Final,
        C.Numero_Capacitacion
    INTO 
        v_Curso_Activo,
        v_Es_Final,
        v_Folio_Curso
    FROM `DatosCapacitaciones` DC
    INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
    WHERE DC.Id_DatosCap = _Id_DatosCap
    LOCK IN SHARE MODE; -- Lectura consistente

    /* Validaciones */
    IF v_Curso_Activo IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El curso solicitado no existe.';
    END IF;

    IF v_Curso_Activo = 0 THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El curso ha sido eliminado o desactivado. No admite inscripciones.';
    END IF;

    /* Si el curso ya terminó (Es_Final = 1), rebotamos la inscripción */
    IF v_Es_Final = 1 THEN
        ROLLBACK;
        SET @ErrMsg = CONCAT('BLOQUEO OPERATIVO [409]: El curso con folio ', v_Folio_Curso, ' ya se encuentra FINALIZADO o CERRADO. No se admiten nuevas inscripciones.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrMsg;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2.2: VERIFICACIÓN DE EXISTENCIA (EVITAR DUPLICADOS)
       ---------------------------------------------------------------------------------------- */
    SELECT `Id_CapPart`, `Fk_Id_CatEstPart`
    INTO v_Id_Existente, v_Estatus_Actual
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_DatosCap` = _Id_DatosCap
      AND `Fk_Id_Usuario` = _Id_Usuario
    FOR UPDATE;

    /* Si ya existe, retornamos éxito idempotente */
    IF v_Id_Existente IS NOT NULL THEN
        COMMIT;
        SELECT 'AVISO: El usuario ya cuenta con un registro en este curso.' AS Mensaje, 
               'REUSADO' AS Accion, 
               v_Id_Existente AS Id_CapPart,
               v_Estatus_Actual AS Id_Estatus_Actual;
        LEAVE THIS_PROC;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 2.3: INSERCIÓN (NUEVA INSCRIPCIÓN)
       ---------------------------------------------------------------------------------------- */
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`, 
        `Fk_Id_Usuario`, 
        `Fk_Id_CatEstPart`, 
        `PorcentajeAsistencia`, 
        `Calificacion`, 
        `created_at`, 
        `updated_at`
    ) VALUES (
        _Id_DatosCap, 
        _Id_Usuario, 
        _Id_Estatus_Ini, -- Aquí entra como 'PENDIENTE' o 'INSCRITO' según quien lo llame
        0.00,  -- Asistencia inicial 0
        NULL,  -- Calificación nula al inicio
        NOW(), 
        NOW()
    );

    /* Confirmación */
    COMMIT;

    SELECT 'ÉXITO: Inscripción registrada correctamente.' AS Mensaje, 
           'INSCRITO' AS Accion, 
           LAST_INSERT_ID() AS Id_CapPart;

END$$

DELIMITER ;