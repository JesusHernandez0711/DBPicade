/* ======================================================================================================
   ARCHIVO: 17__PROCEDIMIENTOS_PARTICIPANTES_CAPACITACIONES.sql
   ======================================================================================================
   
   SISTEMA: PICADE - Gestión de Capacitaciones
   MÓDULO: Gestión de Participantes (Alumnos e Instructores)
   VERSIÓN: 1.0.0
   
   CONTENIDO:
   ----------
   1. SP_Inscribir_Participante          - Registrar usuario como participante en una capacitación
   2. SP_Dar_Baja_Participante           - Cambiar estatus de participante a BAJA
   3. SP_Actualizar_Resultado_Participante - Actualizar calificación/asistencia de un participante
   4. SP_Obtener_Mis_Cursos              - Historial de capacitaciones del participante (Mi Perfil)
   5. SP_Obtener_Cursos_Impartidos       - Historial de cursos impartidos por instructor
   6. SP_Obtener_Participantes_Capacitacion - Lista de participantes de una capacitación específica
   
   DEPENDENCIAS:
   -------------
   - Vista_Capacitaciones
   - Vista_Gestion_de_Participantes
   - vista_usuarios
   - vista_estatus_participante
   - Cat_Estatus_Participante (IDs hardcoded: 1=INSCRITO, 5=BAJA)
   - Cat_Estatus_Capacitacion (IDs hardcoded para validación de estatus operativos)
   
   ====================================================================================================== */

USE Picade;

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
    
    /*
    -- 3.1 Verificar que la capacitación (detalle) exista
    SELECT 
        COUNT(*),
        COALESCE(`DC`.`Activo`, 0),
        COALESCE(`DC`.`Fk_Id_Capacitacion`, 0),
        COALESCE(`DC`.`Fk_Id_CatEstCap`, 0)
    INTO 
        v_Capacitacion_Existe,
        v_Capacitacion_Activa,
        v_Id_Capacitacion_Padre,
        v_Estatus_Curso
    FROM `DatosCapacitaciones` `DC`
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;
    
    IF v_Capacitacion_Existe = 0 THEN
        SELECT 
            'ERROR DE EXISTENCIA [404]: La Capacitación especificada no existe en el sistema.' AS Mensaje,
            'RECURSO_NO_ENCONTRADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;
    
    -- 3.2 Verificar que la capacitación esté activa (no archivada)
    IF v_Capacitacion_Activa = 0 THEN
        SELECT 
            'ERROR DE NEGOCIO [409]: La Capacitación está ARCHIVADA o INACTIVA. No se pueden inscribir participantes.' AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;
    
    -- 3.3 Obtener el folio del curso para mensajes
    SELECT `Numero_Capacitacion` INTO v_Folio_Curso
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- 3.4 Verificar que el estatus del curso permita inscripciones
    --     (No se puede inscribir en cursos FINALIZADOS, CANCELADOS, ARCHIVADOS)
    SELECT `Es_Final` INTO v_Es_Estatus_Final
    FROM `Cat_Estatus_Capacitacion`
    WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: La Capacitación "', v_Folio_Curso, '" tiene un estatus FINAL. No se permiten nuevas inscripciones.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;*/

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
    /*
    -- 5.1 Obtener el cupo máximo programado
    SELECT COALESCE(`C`.`Asistentes_Programados`, 0) INTO v_Cupo_Maximo
    FROM `Capacitaciones` `C`
    WHERE `C`.`Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- 5.2 Contar asientos REALMENTE ocupados (excluyendo BAJAS)
    SELECT COUNT(*) INTO v_Asientos_Ocupados
    FROM Capacitaciones_Participantes
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion
      AND `Fk_Id_CatEstPart` NOT IN (c_ESTATUS_BAJA);  -- Excluye BAJA (5)
    
    -- 5.3 Calcular disponibilidad
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- 5.4 Validar que haya cupo
    IF v_Cupo_Disponible <= 0 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO. La capacitación "', v_Folio_Curso, 
                   '" tiene ', v_Cupo_Maximo, ' lugares y todos están ocupados. ',
                   'Asientos ocupados: ', v_Asientos_Ocupados, '.') AS Mensaje,
            'CUPO_LLENO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;  -- ← Usar la etiqueta
    END IF;*/

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

/* ======================================================================================================
   PROCEDIMIENTO 2: SP_Dar_Baja_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Cambiar el estatus de un participante a BAJA, liberando su cupo para otro usuario.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El registro de participante debe existir.
   2. El participante no debe estar ya dado de BAJA.
   3. No se puede dar de baja si ya tiene calificación registrada (curso en evaluación/finalizado).
   4. El cambio a BAJA libera el asiento para otro participante.
   
   PARÁMETROS:
   -----------
   @_Id_Usuario_Ejecutor  : Quien realiza la operación
   @_Id_Registro_Participante : ID del registro en Capacitaciones_Participantes
   @_Motivo_Baja : Justificación de la baja (obligatorio)
   
   ====================================================================================================== */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS `SP_Dar_Baja_Participante`$$
CREATE PROCEDURE `SP_Dar_Baja_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Motivo_Baja VARCHAR(253)
)
ProcBajarPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;
    DECLARE v_Id_Detalle INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    
    -- Constantes
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- Handler para errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR TÉCNICO [500]: Error interno al procesar la baja del participante.' AS Mensaje,
            'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Motivo_Baja IS NULL OR TRIM(_Motivo_Baja) = '' THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El motivo de la baja es obligatorio para fines de auditoría.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIÓN DEL EJECUTOR
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
    AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 
            'ERROR DE PERMISOS [403]: Usuario Ejecutor no válido o inactivo.' AS Mensaje,
            'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DEL REGISTRO DE PARTICIPANTE
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        COUNT(*),
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),
        COALESCE(`CP`.`Fk_Id_DatosCap`, 0),
        CASE WHEN `CP`.`Calificacion` IS NOT NULL 
        THEN 1 ELSE 0 END
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual,
        v_Id_Detalle,
        v_Tiene_Calificacion
    FROM `Capacitaciones_Participantes` `CP`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 
            'ERROR DE EXISTENCIA [404]: El registro de participante no existe.' AS Mensaje,
            'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    -- Obtener contexto para mensajes
    SELECT 
        `C`.`Numero_Capacitacion`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`)
    INTO v_Folio_Curso, v_Nombre_Participante
    FROM `Capacitaciones_Participantes` `CP`
    JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP.Id_CapPart` = _Id_Registro_Participante;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE REGLAS DE NEGOCIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 3.1 Verificar que no esté ya dado de baja
    IF v_Estatus_Actual = c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('AVISO: El participante "', v_Nombre_Participante, 
                   '" ya tiene estatus de BAJA en el curso "', v_Folio_Curso, '".') AS Mensaje,
            'SIN_CAMBIOS' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    -- 3.2 Verificar que no tenga calificación (curso no evaluado)
    IF v_Tiene_Calificacion = 1 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: No se puede dar de baja al participante "', v_Nombre_Participante,
                   '" porque ya tiene una calificación registrada en el curso "', v_Folio_Curso, 
                   '". El curso está en proceso de evaluación o finalizado.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: EJECUCIÓN DEL CAMBIO DE ESTATUS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
		`Fk_Id_CatEstPart` = c_ESTATUS_BAJA,
    /* [CORRECCIÓN]: Guardamos la justificación y la auditoría */
        `Justificacion` = _Motivo_Baja,
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT(' BAJA REGISTRADA: El participante "', v_Nombre_Participante,
               '" ha sido dado de baja del curso "', v_Folio_Curso, 
               '". Motivo: ', _Motivo_Baja, '. El cupo ha sido liberado.') AS Mensaje,
        'BAJA_EXITOSA' AS Accion;

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO 3: SP_Actualizar_Resultado_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Actualizar la calificación y/o porcentaje de asistencia de un participante.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El registro de participante debe existir.
   2. No se puede actualizar si el participante está de BAJA.
   3. La calificación debe estar entre 0 y 100.
   4. El porcentaje de asistencia debe estar entre 0 y 100.
   5. Al asignar calificación, el estatus cambia automáticamente (APROBADO/REPROBADO).
   
   ====================================================================================================== */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS `SP_Actualizar_Resultado_Participante`$$
CREATE PROCEDURE `SP_Actualizar_Resultado_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Calificacion DECIMAL(5,2),
    IN _Porcentaje_Asistencia DECIMAL(5,2),
    IN _Id_Estatus_Resultado INT,  -- NULL = Calcular automático basado en calificación
    IN _Observaciones VARCHAR(253) -- [NUEVO] Feedback cualitativo (Opcional)
)
ProcUpdatResulPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    /* VARIABLES */
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    DECLARE v_Nuevo_Estatus INT DEFAULT 0;
    
    -- Constantes de estatus
    DECLARE c_ESTATUS_ASISTIO INT DEFAULT 2;
    DECLARE c_ESTATUS_APROBADO INT DEFAULT 3;
    DECLARE c_ESTATUS_REPROBADO INT DEFAULT 4;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    DECLARE c_CALIFICACION_MINIMA_APROBATORIA DECIMAL(5,2) DEFAULT 70.00;
    
    -- Handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR TÉCNICO [500]: Error interno al actualizar resultados.' AS Mensaje,
            'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Validar rango de calificación
    IF _Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: La calificación debe estar entre 0 y 100.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Validar rango de asistencia
    IF _Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: El porcentaje de asistencia debe estar entre 0 y 100.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIONES DE EXISTENCIA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) INTO v_Ejecutor_Existe
    FROM Usuarios WHERE Id_Usuario = _Id_Usuario_Ejecutor AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR DE PERMISOS [403]: Usuario Ejecutor no válido.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    SELECT 
        COUNT(*),
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0)
    INTO v_Registro_Existe, v_Estatus_Actual
    FROM `Capacitaciones_Participantes` `CP`
    WHERE `CP.Id_CapPart` = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 'ERROR DE EXISTENCIA [404]: El registro de participante no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Obtener contexto
    SELECT 
        `C`.`Numero_Capacitacion`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`)
    INTO v_Folio_Curso, v_Nombre_Participante
    FROM `Capacitaciones_Participantes` `CP`
    JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;
    
    -- No se puede actualizar participante dado de baja
    IF v_Estatus_Actual = c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: No se pueden actualizar resultados del participante "', 
                   v_Nombre_Participante, '" porque está dado de BAJA.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: DETERMINAR NUEVO ESTATUS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- Usar estatus proporcionado explícitamente
        SET v_Nuevo_Estatus = _Id_Estatus_Resultado;
    ELSEIF _Calificacion IS NOT NULL THEN
        -- Calcular automáticamente basado en calificación
        IF _Calificacion >= c_CALIFICACION_MINIMA_APROBATORIA THEN
            SET v_Nuevo_Estatus = c_ESTATUS_APROBADO;
        ELSE
            SET v_Nuevo_Estatus = c_ESTATUS_REPROBADO;
        END IF;
    ELSEIF _Porcentaje_Asistencia IS NOT NULL THEN
        -- Solo asistencia, sin calificación
        SET v_Nuevo_Estatus = c_ESTATUS_ASISTIO;
    ELSE
        -- Mantener estatus actual
        SET v_Nuevo_Estatus = v_Estatus_Actual;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: EJECUCIÓN DE LA ACTUALIZACIÓN
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
        `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
        `Fk_Id_CatEstPart` = v_Nuevo_Estatus,
        
        /* AQUÍ ESTÁ EL CAMBIO: */
        /* Si mandan observación, la guardamos. Si mandan NULL, respetamos lo que ya había (o lo dejamos NULL). */
        `Justificacion` = COALESCE(_Observaciones, `Justificacion`),
        
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
       
        /* RESPUESTA */
    SELECT 
        CONCAT('RESULTADO GUARDADO: "', v_Nombre_Participante, '". ',
               IF(_Calificacion IS NOT NULL, CONCAT('Nota: ', _Calificacion, '. '), ''),
               IF(_Observaciones IS NOT NULL AND _Observaciones != '', ' (Con observaciones).', '')
        ) AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO 4: SP_Obtener_Mis_Cursos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Alimentar la sección "Mi Historial de Capacitación" en el Perfil del Usuario (Participante).
   Muestra ÚNICAMENTE la última versión (vigente) de cada capacitación para evitar duplicados.
   
   ARQUITECTURA:
   -------------
   Implementa el patrón "Latest Snapshot" para garantizar que cada capacitación aparezca
   solo UNA vez, mostrando la información más actualizada.
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Obtener_Mis_Cursos`$$

CREATE PROCEDURE `SP_Obtener_Mis_Cursos`(
    IN _Id_Usuario INT
)
ProcMisCursos: BEGIN
    
    /* VALIDACIÓN DE ENTRADA */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario es obligatorio.' AS Mensaje;
        LEAVE ProcMisCursos;
    END IF;

    /* CONSULTA DE HISTORIAL
       Objetivo: Mostrar cursos Activos Y Archivados, pero solo una vez (la última versión).
    */
    SELECT 
        /* IDs para navegación */
        `VGP`.`Id_Registro_Participante`,
        `VGP`.`Id_Detalle_de_Capacitacion`,
        `VGP`.`Folio_Curso`,
        
        /* Información del Curso */
        `VGP`.`Tema_Curso`,
        `VGP`.`Fecha_Inicio`,
        `VGP`.`Fecha_Fin`,
        `VGP`.`Duracion_Horas`,
        `VGP`.`Sede`,
        `VGP`.`Modalidad`,
        `VGP`.`Instructor_Asignado`,
        `VGP`.`Estatus_Global_Curso`, -- Muestra "FINALIZADO", "ARCHIVADO", et`C`.
        
        /* Resultados del Usuario */
        `VGP`.`Porcentaje_Asistencia`,
        `VGP`.`Calificacion_Numerica`,
        `VGP`.`Resultado_Final` AS `Estatus_Participante`,
        `VGP`.`Detalle_Resultado`,
        `VGP`.`Nota_Auditoria`  AS `Justificacion`, -- Columna nueva
        
        /* Metadata */
        `VGP`.`Fecha_Inscripcion`,
        `VGP`.`Fecha_Ultima_Modificacion`

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    
    /* JOIN para filtrar por usuario */
    INNER JOIN `Picade`.`capacitaciones_participantes` `CP`
        ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
        
    WHERE `CP`.`Fk_Id_Usuario` = _Id_Usuario
    
    /* FILTRO INTELIGENTE (SNAPSHOT):
       En lugar de filtrar por 'Activo=1' (que oculta los archivados),
       filtramos para obtener SOLO la versión más reciente (ID más alto)
       que tenga este folio para este usuario.
       
       Esto elimina los duplicados históricos pero mantiene los cursos terminados/archivados.
    */
    AND `VGP`.`Id_Detalle_de_Capacitacion` = (
        SELECT MAX(`VSub`.`Id_Detalle_de_Capacitacion`)
        FROM `Picade`.`Vista_Gestion_de_Participantes` `VSub`
        INNER JOIN `Picade`.`capacitaciones_participantes` `CPSub` 
            ON `VSub`.`Id_Registro_Participante` = `CPSub`.`Id_CapPart`
        WHERE `VSub`.`Folio_Curso` = `VGP`.`Folio_Curso` -- Mismo Folio (Curso Padre)
          AND `CPSub`.`Fk_Id_Usuario` = _Id_Usuario -- Mismo Usuario
    )
    
    /* ORDENAMIENTO: Lo más reciente primero */
    ORDER BY `VGP`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO 5: SP_Obtener_Cursos_Impartidos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Mostrar el historial de cursos que un instructor ha impartido.
   Útil para el perfil del instructor y para auditorías de carga docente.
   
   ARQUITECTURA:
   -------------
   Similar a SP_Obtener_Mis_Cursos pero filtrado por el campo Fk_Id_Instructor
   en lugar de la tabla de participantes.
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Obtener_Cursos_Impartidos`$$

CREATE PROCEDURE `SP_Obtener_Cursos_Impartidos`(
    IN _Id_Instructor INT
)
ProcCursosImpart: BEGIN
    
    /* VALIDACIÓN DE ENTRADA */
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio.' AS Mensaje;
        LEAVE ProcCursosImpart;
    END IF;

    /* CONSULTA MAESTRA DE INSTRUCTOR
       Objetivo: Mostrar historial de cursos impartidos (Activos y Archivados).
       Usa la 'Vista_Capacitaciones' para simplificar la lectura.
    */
    SELECT 
        /* IDs para navegación */
        `VC`.`Id_Capacitacion`,
        `VC`.Id_Detalle_de_Capacitacion,
        `VC`.Numero_Capacitacion          AS Folio_Curso,
        
        /* Información del Curso */
        `VC`.`Nombre_Tema`                  AS `Tema_Curso`,
        `VC`.`Duracion_Horas`,
        `VC`.`Clave_Gerencia_Solicitante`   AS `Gerencia_Solicitante`,
        
        /* Logística */
        `VC`.`Nombre_Sede`                  AS `Sede`,
        `VC`.`Nombre_Modalidad`             AS `Modalidad`,
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        
        /* Métricas */
        `VC`.`Asistentes_Meta`              AS `Cupo_Programado`,
        `VC`.`Asistentes_Reales`,
        
        /* [OPTIMIZACIÓN]: Ya no calculamos, solo leemos de la vista */
        `VC`.`Participantes_Activos`,
        
        /* Cálculo en tiempo real de Participantes Activos (Sin Bajas) */
        /* (
            SELECT COUNT(*) 
            FROM Picade.Capacitaciones_Participantes CP 
            WHERE CP.Fk_Id_DatosCap = `VC`.Id_Detalle_de_Capacitacion
              AND CP.Fk_Id_CatEstPart != 5 -- Excluir BAJA
        )                               AS Participantes_Activos,
        
        Estatus */
        -- `VC`.Estatus_Curso,
        -- `VC`.Codigo_Estatus,              -- Útil para colores en Frontend
        -- `VC`.Estatus_del_Registro         AS Es_Version_Vigente
        
        /* Estatus "Congelado" */
        `VC`.`Estatus_Curso`                AS `Estatus_Snapshot`,
        
        /* [NUEVO] SEMÁFORO DE VIGENCIA 
           Esto resuelve tu duda. Le dice al usuario si este registro sigue vivo o si es historia.
        */
        CASE 
            WHEN `DC`.`Activo` = 1 
            THEN 'ACTUAL'      -- Sigue siendo el responsable
            ELSE 'HISTORIAL'                      -- Fue responsable, ya no (o ya acabó)
        END                             AS `Tipo_Registro`,

        /* [OPCIONAL] BANDERA BOOLEANA
           Para que el Frontend ponga el renglón en gris si es 0
        */
        `DC`.`Activo`                       AS `Es_Version_Vigente`,

        /* Metadata */
        `DC`.`created_at`                   AS `Fecha_Asignacion`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* FILTRO MAESTRO: Solo cursos donde este usuario es el instructor */
    /* Nota: Usamos la vista, pero el filtro debe ser sobre el ID real, 
       así que hacemos un join ligero con la tabla física para asegurar el ID */
    INNER JOIN `Picade`.`DatosCapacitaciones` `DC` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
        
    WHERE `DC`.`Fk_Id_Instructor` = _Id_Instructor
    
    /* FILTRO SNAPSHOT INTELIGENTE:
       1. Si el curso sigue activo con este instructor -> Lo muestra.
       2. Si el curso se archivó (finalizó) con este instructor -> Lo muestra.
       3. Si el curso se reasignó a otro instructor en una versión posterior ->
          Muestra la versión histórica donde ESTE instructor dio la clase.
       
       Lógica: Mostramos la MAX(Version) PARA ESTE INSTRUCTOR ESPECÍFICO.
    */
    AND `DC`.`Id_DatosCap` = (
        SELECT MAX(`DC2`.`Id_DatosCap`)
        FROM `Picade`.`DatosCapacitaciones` `DC2`
        WHERE `DC2`.`Fk_Id_Capacitacion` = `VC`.`Id_Capacitacion`
          AND `DC2`.`Fk_Id_Instructor` = _Id_Instructor -- Clave: Max versión DE ÉL
    )
    
    /* ORDENAMIENTO: Cronológico inverso */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO 6: SP_Obtener_Participantes_Capacitacion
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Obtener la lista completa de participantes de una capacitación específica.
   Alimenta el grid de "Gestión de Participantes" en el módulo de Coordinador.
   
   INCLUYE:
   - Información completa del participante
   - Estatus actual (INSCRITO, ASISTIÓ, APROBADO, REPROBADO, BAJA)
   - Calificación y asistencia
   - Indicador visual de cupo
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Obtener_Participantes_Capacitacion`$$

CREATE PROCEDURE `SP_Obtener_Participantes_Capacitacion`(
    IN _Id_Detalle_Capacitacion INT
)
ProcPartCapac: BEGIN

    /* -------------------------------------------------------------------------
       VALIDACIÓN
       ------------------------------------------------------------------------- */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: ID obligatorio.' AS Mensaje; 
        LEAVE ProcPartCapac;
    END IF;

    /* -------------------------------------------------------------------------
       RESULTSET 1: MÉTRICAS PARA LA CABECERA DEL GRID
       Esto sirve para refrescar los contadores: "18/20 inscritos".
       ------------------------------------------------------------------------- */
    SELECT 
        `VC`.`Numero_Capacitacion`     AS `Folio_Curso`,
        /* [KPIs de Cobertura] */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Manuales`, -- El campo que pueden editar
        
        /* [OPTIMIZACIÓN]: Dato directo de la vista */        
		/* [NUEVO] CAMPOS DIRECTOS DE LA VISTA */
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   -- El dato automático
        `VC`.`Total_Impacto_Real`          AS `Total_Asistentes_Reales`,         -- El resultado final (GREATEST)
        `VC`.`Participantes_Baja`,
        `VC`.`Cupo_Disponible`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    WHERE `VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion;

    /* -------------------------------------------------------------------------
       RESULTSET 2: DATOS PARA EL GRID (TABLA)
       Lista pura de alumnos. Tu Frontend decide si pinta la fila roja o verde
       basándose en 'Estatus_Participante'.
       ------------------------------------------------------------------------- */
    SELECT 
        /* IDs para acciones (Editar/Borrar) */
        `VGP`.`Id_Registro_Participante`   AS `Id_Inscripcion`,
        
        /* Datos Visuales */
        `VGP`.`Ficha_Participante`         AS `Ficha`,
        CONCAT(`VGP`.`Ap_Paterno_Participante`, ' ', `VGP`.`Ap_Materno_Participante`, ' ', `VGP`.`Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        
        /* Inputs Editables */
        `VGP`.`Porcentaje_Asistencia`      AS `Asistencia`,
        `VGP`.`Calificacion_Numerica`      AS `Calificacion`,
        
        /* Estado */
        `VGP`.`Resultado_Final`            AS `Estatus_Participante`, -- Texto: 'INSCRITO', 'BAJA', et`C`.
        `VGP`.`Detalle_Resultado`          AS `Descripcion_Estatus`,  -- Texto descriptivo
        `VGP`.`Nota_Auditoria`             AS `Justificacion`         -- Texto: Motivo de la baja/calificación

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* Orden: Primero apellidos A-Z. (Opcional: Bajas al final) */
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC, `VGP`.`Ap_Materno_Participante` ASC;

END$$
DELIMITER ;

/* ======================================================================================================
   PROCEDIMIENTO 7: SP_Reinscribir_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Reactivar un participante que estaba dado de BAJA, cambiando su estatus a INSCRITO.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El participante debe existir y estar en estatus BAJA.
   2. Debe haber cupo disponible para reactivarlo.
   3. El curso debe estar en estatus operativo (no FINALIZADO/CANCELADO/ARCHIVADO).
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Reinscribir_Participante`$$

CREATE PROCEDURE `SP_Reinscribir_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Motivo_Reinscripcion VARCHAR(253)
)
ProcReinsPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Id_Detalle INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Curso_Activo INT DEFAULT 0; -- Para verificar si el curso sigue vivo
    
    -- Constantes
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- Handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'ERROR TÉCNICO [500]: Error interno al procesar la reinscripción.' AS Mensaje, 'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIONES DE EXISTENCIA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    /* 1.1 Ejecutor */
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR DE PERMISOS [403]: Usuario Ejecutor no válido.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    /* 1.2 Registro del Participante y Contexto */
    SELECT 
        COUNT(*),
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),
        COALESCE(`CP`.`Fk_Id_DatosCap`, 0),
        
        -- Contexto para Mensajes
        `C`.`Numero_Capacitacion`,
        `C`.`Asistentes_Programados`,
        CONCAT(`IP.Nombre`, ' ', `IP.Apellido_Paterno`),
        `DC`.`Activo` -- Verificamos si la versión del curso está Activa (1) o Archivada (0)
        
    INTO v_Registro_Existe,
		v_Estatus_Actual,
        v_Id_Detalle, 
        v_Folio_Curso,
        v_Cupo_Maximo, 
        v_Nombre_Participante, 
        v_Curso_Activo
         
    FROM `Capacitaciones_Participantes` `CP`
    JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 'ERROR DE EXISTENCIA [404]: El registro de participante no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DE REGLAS DE NEGOCIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 2.1 Verificar que esté dado de BAJA (Solo se puede reinscribir a alguien dado de baja)
    IF v_Estatus_Actual != c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('AVISO: El participante "', v_Nombre_Participante, 
                   '" NO está dado de baja (Estatus actual: ', v_Estatus_Actual, '). No requiere reinscripción.') AS Mensaje,
            'SIN_CAMBIOS' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    -- 2.2 Verificar que el curso siga VIGENTE (Activo = 1)
    IF v_Curso_Activo = 0 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: No se puede reinscribir en el curso "', v_Folio_Curso, 
                   '" porque esta versión ya fue FINALIZADA o ARCHIVADA.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    -- 2.3 Verificar cupo disponible (Contando a todos MENOS los de baja)
    SELECT COUNT(*) 
    INTO v_Asientos_Ocupados
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_DatosCap` = v_Id_Detalle
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA; -- Misma lógica que en la Vista
    
    IF v_Asientos_Ocupados >= v_Cupo_Maximo THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO (', v_Asientos_Ocupados, '/', v_Cupo_Maximo, '). No hay espacio para reinscribir a "', 
                   v_Nombre_Participante, '".') AS Mensaje,
            'CUPO_LLENO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: EJECUCIÓN (CON AUDITORÍA)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_CatEstPart` = c_ESTATUS_INSCRITO, -- Vuelve a estar Activo (ID 1)
        
        /* [IMPORTANTE] Guardamos el motivo en la columna Justificación */
        `Justificacion` = CONCAT('REINSCRIPCIÓN: ', COALESCE(_Motivo_Reinscripcion, 'Sin motivo')),
        
        /* [IMPORTANTE] Auditoría de Modificación */
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT('REINSCRIPCIÓN EXITOSA: "', v_Nombre_Participante,
               '" reactivado en "', v_Folio_Curso, '".') AS Mensaje,
        'REINSCRITO' AS Accion;

END$$

DELIMITER ;

/* ======================================================================================================
   FIN DEL ARCHIVO: 17__PROCEDIMIENTOS_PARTICIPANTES_CAPACITACIONES.sql
   ======================================================================================================
   
   RESUMEN DE PROCEDIMIENTOS CREADOS:
   ----------------------------------
   1. SP_Inscribir_Participante          - Registrar usuario como participante (con validación de cupo)
   2. SP_Dar_Baja_Participante           - Cambiar estatus a BAJA (libera cupo)
   3. SP_Actualizar_Resultado_Participante - Actualizar calificación/asistencia
   4. SP_Obtener_Mis_Cursos              - Historial del participante (Latest Snapshot)
   5. SP_Obtener_Cursos_Impartidos       - Historial del instructor (Latest Snapshot)
   6. SP_Obtener_Participantes_Capacitacion - Lista de participantes de un curso
   7. SP_Reinscribir_Participante        - Reactivar participante dado de baja
   
   MAPEO DE ESTATUS DE PARTICIPANTE:
   ---------------------------------
   | ID | Nombre    | Descripción                          |
   |----|-----------|--------------------------------------|
   | 1  | INSCRITO  | Participante registrado en el curso  |
   | 2  | ASISTIÓ   | Participante con asistencia          |
   | 3  | APROBADO  | Calificación >= 70                   |
   | 4  | REPROBADO | Calificación < 70                    |
   | 5  | BAJA      | Dado de baja (libera cupo)           |
   
   ====================================================================================================== */