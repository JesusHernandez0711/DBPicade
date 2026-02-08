/* ======================================================================================================
   PROCEDIMIENTO: SP_Autoinscribir_Participante
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_Autoinscribir_Participante
   - Clasificación:        Transacción de Auto-Servicio (Self-Service Transaction)
   - Nivel de Aislamiento: READ COMMITTED
   - Perfil de Acceso:     Usuario Final (Alumno/Empleado)
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento permite que un usuario activo se registre a sí mismo en una capacitación.
   A diferencia de la inscripción administrativa, este proceso es más estricto:
   - No permite overrides manuales.
   - Aplica rigurosamente la validación de cupo híbrido.
   - El usuario actúa como 'Juez y Parte' en la auditoría (Created_By = Self).

   ------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE VALIDACIÓN
   ------------------------------------------------------------------------------------------------------
   1. Identidad: ¿Quien soy? (El usuario debe existir y estar activo).
   2. Disponibilidad: ¿El curso está abierto? (No archivado, no finalizado).
   3. Idempotencia: ¿Ya estoy dentro? (Evitar doble clic).
   4. Capacidad: ¿Hay lugar para mí? (Respetando el bloqueo manual de coordinadores).

   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Autoinscribir_Participante`$$

CREATE PROCEDURE `SP_Autoinscribir_Participante`(
    IN _Id_Usuario INT,              -- [INPUT]: ID del usuario que se inscribe (Ejecutor y Victima son el mismo)
    IN _Id_Detalle_Capacitacion INT  -- [INPUT]: ID de la Versión del Curso
)
ProcAutoIns: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- [VALIDACIÓN DE USUARIO]
    DECLARE v_Usuario_Existe INT DEFAULT 0;
    DECLARE v_Usuario_Activo INT DEFAULT 0;
    
    -- [CONTEXTO DEL CURSO]
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Estatus_Curso INT DEFAULT 0;
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;
    
    -- [LÓGICA HÍBRIDA DE CUPO]
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Conteo_Sistema INT DEFAULT 0;
    DECLARE v_Conteo_Manual INT DEFAULT 0;     -- Factor crítico: El usuario respeta el bloqueo manual
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Cupo_Disponible INT DEFAULT 0;
    
    -- [CONTROL]
    DECLARE v_Ya_Inscrito INT DEFAULT 0;
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;
    
    -- [CONSTANTES]
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;

    /* HANDLER DE ERRORES */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR DE SISTEMA [500]: Ocurrió un error al procesar tu inscripción.' 
            AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN (FAIL-FAST)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
			SELECT 'ERROR DE SESIÓN [400]: No se pudo identificar tu usuario.' 
			AS Mensaje, 
            'LOGOUT_REQUIRED' AS Accion, 
			NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: Curso no válido.' 
			AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion, 
			NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE IDENTIDAD (SELF-CHECK)
       Objetivo: Asegurar que el usuario solicitante tiene permiso de operar.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*), `Activo` 
    INTO v_Usuario_Existe, v_Usuario_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario;
    
    IF v_Usuario_Existe = 0 
		THEN
			SELECT 'ERROR DE CUENTA [404]: Tu usuario no parece existir en el sistema.' 
            AS Mensaje, 
            'CONTACTAR_SOPORTE' AS Accion, 
            NULL AS Id_Registro_Participante;
			LEAVE ProcAutoIns;
    END IF;
    
    IF v_Usuario_Activo = 0 
		THEN
			SELECT 'ACCESO DENEGADO [403]: Tu cuenta está inactiva. No puedes inscribirte.' 
            AS Mensaje, 
            'ACCESO_DENEGADO' AS Accion, 
            NULL AS Id_Registro_Participante;
			LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: CONTEXTO DEL CURSO
       Objetivo: Validar que el curso está disponible para el público.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*), 
        COALESCE(`DC`.`Activo`, 0), 
        `DC`.`Fk_Id_Capacitacion`, 
        `DC`.`Fk_Id_CatEstCap`, 
        COALESCE(`DC`.`AsistentesReales`, 0) 
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    IF v_Capacitacion_Existe = 0 THEN
        SELECT 'ERROR [404]: El curso que buscas no existe.' 
        AS Mensaje, 
        'RECURSO_NO_ENCONTRADO' AS Accion, 
        NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    IF v_Capacitacion_Activa = 0 THEN
        SELECT 'LO SENTIMOS [409]: Este curso ha sido archivado o cancelado.' 
        AS Mensaje, 
        'CURSO_CERRADO' AS Accion, 
        NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Obtener Meta y Folio
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- Validar si el curso ya finalizó
    SELECT `Es_Final` 
    INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 
		THEN
			SELECT CONCAT('INSCRIPCIONES CERRADAS: El curso "', v_Folio_Curso, '" ya ha finalizado.') 
			AS Mensaje, 
            'CURSO_CERRADO' AS Accion, 
			NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE UNICIDAD
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) 
    INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
		AND `Fk_Id_Usuario` = _Id_Usuario;
    
    IF v_Ya_Inscrito > 0 
		THEN
			SELECT 'YA ESTÁS INSCRITO: Ya tienes un lugar reservado en este curso.' 
            AS Mensaje, 
            'YA_INSCRITO' AS Accion, 
            NULL AS Id_Registro_Participante;
			LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE CUPO (LÓGICA HÍBRIDA)
       Nota: Si el coordinador puso manual=30 y la meta es 30, el cupo será 0 para el usuario.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1. Contar asientos ocupados reales en sistema
    SELECT COUNT(*) 
    INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
		AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- 2. Aplicar regla del máximo (Pesimista)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- 3. Calcular disponibilidad
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    IF v_Cupo_Disponible <= 0 
		THEN
			SELECT 'CUPO LLENO: Lo sentimos, ya no hay lugares disponibles para este curso.' AS Mensaje, 'CUPO_LLENO' AS Accion, NULL AS Id_Registro_Participante;
			LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: EJECUCIÓN (AUTOREGISTRO)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` 
    (
        `Fk_Id_DatosCap`, 
        `Fk_Id_Usuario`, 
        `Fk_Id_CatEstPart`, 
        `Calificacion`, 
        `PorcentajeAsistencia`, 
        `created_at`, 
        `updated_at`, 
        `Fk_Id_Usuario_Created_By`, -- [AUDITORÍA]: Se registra a sí mismo
        `Fk_Id_Usuario_Updated_By`
    ) VALUES (
        _Id_Detalle_Capacitacion, 
        _Id_Usuario, 
        c_ESTATUS_INSCRITO, 
        NULL, 
        NULL, 
        NOW(), NOW(), 
        _Id_Usuario,  -- Auto-registro
        _Id_Usuario
    );
    
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 6: FEEDBACK AL USUARIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('¡REGISTRO EXITOSO! Te has inscrito correctamente al curso "', v_Folio_Curso, '".') AS Mensaje,
        'INSCRITO' AS Accion,
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$
DELIMITER ;