/* ======================================================================================================
   PROCEDIMIENTO 1: SP_Inscribir_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Registrar un usuario como participante/alumno en una capacitación específica.
   Implementa validación de cupo inteligente que excluye participantes con estatus BAJA.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El usuario a inscribir debe existir y estar activo en el sistema.
   2. La capacitación debe existir y estar en estatus operativo (no ARCHIVADO/CANCELADO).
   3. El usuario no puede estar ya inscrito en la misma versión del curso.
   4. Debe haber cupo disponible (excluyendo participantes dados de BAJA).
   5. El participante inicia con estatus "INSCRITO" (ID=1).
   
   PARÁMETROS:
   -----------
   @_Id_Usuario_Ejecutor  : Quien realiza la operación (Coordinador/Admin)
   @_Id_Detalle_Capacitacion : ID de la versión específica del curso (DatosCapacitaciones)
   @_Id_Usuario_Participante : Usuario a inscribir como participante
   
   RETORNO:
   --------
   Resultset con: Mensaje, Accion, Id_Registro_Participante
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Inscribir_Participante`$$

CREATE PROCEDURE `SP_Inscribir_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Detalle_Capacitacion INT,
    IN _Id_Usuario_Participante INT
)
ProcInsPart: BEGIN   -- ← Agregar etiqueta aquí
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES LOCALES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- Variables de validación
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Participante_Existe INT DEFAULT 0;
    DECLARE v_Participante_Activo INT DEFAULT 0;
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;
    DECLARE v_Ya_Inscrito INT DEFAULT 0;
    
    -- Variables de cupo
/* Variables de Cupo Híbrido */
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Conteo_Sistema INT DEFAULT 0;
    DECLARE v_Conteo_Manual INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Cupo_Disponible INT DEFAULT 0;
    
    -- Variables de contexto
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Estatus_Curso INT DEFAULT 0;
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;
    
    -- Variable de resultado
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;
    
    -- Constantes de estatus de participante
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- Handler para errores SQL
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR TÉCNICO [500]: Error interno durante la inscripción del participante.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE INPUTS (FAIL FAST)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 0.1 Validar ID del ejecutor
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio y debe ser válido.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;
    
    -- 0.2 Validar ID de la capacitación
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Detalle de Capacitación es obligatorio y debe ser válido.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;
    
    -- 0.3 Validar ID del participante
    IF _Id_Usuario_Participante IS NULL OR _Id_Usuario_Participante <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Participante es obligatorio y debe ser válido.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIÓN DE EXISTENCIA Y ESTADO DEL EJECUTOR
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) INTO v_Ejecutor_Existe
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 
            'ERROR DE PERMISOS [403]: El Usuario Ejecutor no existe o no tiene permisos activos en el sistema.' AS Mensaje,
            'ACCESO_DENEGADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DE EXISTENCIA Y ESTADO DEL PARTICIPANTE
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 2.1 Verificar que el usuario participante exista
    SELECT COUNT(*) INTO v_Participante_Existe
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Participante_Existe = 0 THEN
        SELECT 
            'ERROR DE EXISTENCIA [404]: El Usuario que intenta inscribir no existe en el sistema.' AS Mensaje,
            'RECURSO_NO_ENCONTRADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;
    
    -- 2.2 Verificar que el usuario participante esté activo
    SELECT `Activo` 
    INTO v_Participante_Activo
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Participante_Activo = 0 THEN
        SELECT 
            'ERROR DE NEGOCIO [409]: El Usuario que intenta inscribir está INACTIVO. No puede participar en capacitaciones.' AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE EXISTENCIA Y ESTADO DE LA CAPACITACIÓN
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
	/* --------------------------------------------------------------------------------
       FASE 3: EXISTENCIA DE CURSO (ERROR DE INTEGRIDAD [404] / LÓGICA [409])
       -------------------------------------------------------------------------------- */
    SELECT COUNT(*), 
    COALESCE(`DC`.`Activo`, 0), 
		`DC`.`Fk_Id_Capacitacion`, 
		`DC`.`Fk_Id_CatEstCap`, 
    COALESCE(`DC`.`AsistentesReales`, 0)
    INTO v_Capacitacion_Existe, 
		v_Capacitacion_Activa, 
		v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

	IF v_Capacitacion_Existe = 0 THEN
        SELECT 'ERROR DE INTEGRIDAD [404]: La capacitación indicada no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    IF v_Capacitacion_Activa = 0 THEN
        SELECT 'ERROR DE LÓGICA [409]: Esta versión del curso está ARCHIVADA o eliminada.' AS Mensaje, 'CONFLICTO_ESTADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    /* Obtener Folio y Meta */
    SELECT `Numero_Capacitacion`,
		`Asistentes_Programados` -- <--- AQUÍ traemos la meta
	INTO v_Folio_Curso, 
		v_Cupo_Maximo            -- <--- Y la guardamos
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    /* Validar Estatus Final */
    SELECT `Es_Final` INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 THEN
        SELECT CONCAT('ERROR DE LÓGICA [409]: El curso "', v_Folio_Curso, '" ya finalizó o fue cancelado. No admite inscripciones.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE DUPLICIDAD (ANTI-DOBLE INSCRIPCIÓN)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) INTO v_Ya_Inscrito
    FROM Capacitaciones_Participantes
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion
      AND `Fk_Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Ya_Inscrito > 0 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: El Usuario ya está inscrito en esta capacitación ("', v_Folio_Curso, '").') AS Mensaje,
            'DUPLICADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: VALIDACIÓN DE CUPO DISPONIBLE (INTELIGENCIA DE ASIENTOS)
       ═══════════════════════════════════════════════════════════════════════════════════
       LÓGICA DE NEGOCIO:
       - El cupo máximo viene de la cabecera (Capacitaciones.Asistentes_Programados)
       - Los asientos ocupados son participantes con estatus DIFERENTE de BAJA (5)
       - Un participante dado de BAJA libera su asiento para otro
       ═══════════════════════════════════════════════════════════════════════════════════ */
    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: CUPO HÍBRIDO (ERROR DE NEGOCIO [409])
       ═══════════════════════════════════════════════════════════════════════════════════ */
    /* 1. Contar sistema (excluyendo bajas) */
    SELECT COUNT(*) 
    INTO v_Conteo_Sistema
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    /* 2. Regla del Máximo (Sistema vs Manual) */
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    /* 3. Cálculo */
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    /* 4. Validación */
    IF v_Cupo_Disponible <= 0 THEN
        SELECT CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO en "', v_Folio_Curso, '". Ocupados: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo) AS Mensaje, 'CUPO_LLENO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 6: EJECUCIÓN DE LA INSCRIPCIÓN (TRANSACCIÓN ATÓMICA)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    -- 6.1 Insertar el registro de participante
    INSERT INTO Capacitaciones_Participantes (
        `Fk_Id_DatosCap`,
        `Fk_Id_Usuario`,
        `Fk_Id_CatEstPart`,
        `Calificacion`,
        `PorcentajeAsistencia`,
        /* [CORRECCIÓN]: FALTABA AGREGAR ESTOS NOMBRES DE COLUMNA */
        `created_at`,
        `updated_at`,
        `Fk_Id_Usuario_Created_By`,
        `Fk_Id_Usuario_Updated_By`
    ) VALUES (
        _Id_Detalle_Capacitacion,
        _Id_Usuario_Participante,
        c_ESTATUS_INSCRITO,  -- Estatus inicial: INSCRITO (1)
        NULL,                 -- Sin calificación aún
        NULL,                  -- Sin asistencia aún
        /* [NUEVO]: VALORES DE AUDITORÍA */
        NOW(),
        NOW(),
        _Id_Usuario_Ejecutor, -- Quién inscribió
        _Id_Usuario_Ejecutor  -- Quién modificó (al inicio es el mismo)
    );
    
    -- 6.2 Capturar el ID generado
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 7: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT(' INSCRIPCIÓN EXITOSA: El participante ha sido inscrito en la capacitación "', 
               v_Folio_Curso, '". Cupo restante: ', (v_Cupo_Disponible - 1), ' de ', v_Cupo_Maximo, '.') AS Mensaje,
        'INSCRITO' AS Accion,
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$

DELIMITER ;