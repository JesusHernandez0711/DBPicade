/* ======================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacionParticipante
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_CambiarEstatusCapacitacionParticipante
   - Clasificación:        Transacción de Estado Conmutativo (Toggle State Transaction)
   - Nivel de Aislamiento: READ COMMITTED
   - Perfil de Acceso:     Coordinador / Administrador
   - Dependencias:         Tablas: Usuarios, DatosCapacitaciones, Capacitaciones_Participantes.
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento actúa como un INTERRUPTOR INTELIGENTE para el ciclo de vida del participante.
   Determina automáticamente la acción a realizar basándose en el estado actual del registro:
   
   [ESCENARIO A: EL ALUMNO ESTÁ ACTIVO (INSCRITO/ASISTIÓ/ETC)]
   -> ACCIÓN: DAR DE BAJA.
   -> REGLAS: 
      1. No se puede dar de baja si ya tiene calificación (Integridad Histórica).
      2. Liberar el cupo inmediatamente.
   
   [ESCENARIO B: EL ALUMNO ESTÁ EN BAJA]
   -> ACCIÓN: REINSCRIBIR (REACTIVAR).
   -> REGLAS:
      1. Verificar Cupo Híbrido (Meta - Max(Sistema, Manual)).
      2. No permitir si el curso está Cancelado/Archivado.
   
   [AUDITORÍA]:
   Se registra el motivo del cambio de estado, proporcionando trazabilidad completa de por qué
   entró o salió el participante.

   ------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE DECISIÓN (FLOWCHART)
   ------------------------------------------------------------------------------------------------------
   IF (Estatus == BAJA) THEN
       EXECUTE Lógica_Reinscripcion()
   ELSE
       EXECUTE Lógica_Baja()
   END IF

   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacionParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacionParticipante`(
    IN _Id_Usuario_Ejecutor INT,       -- Admin que realiza el cambio
    IN _Id_Registro_Participante INT,  -- ID del registro (PK)
    IN _Motivo_Cambio VARCHAR(250)     -- Justificación obligatoria para cualquier sentido
)
ProcTogglePart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: DECLARACIÓN DE VARIABLES Y MEMORIA
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Validación y Contexto
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;
    DECLARE v_Id_Padre INT DEFAULT 0;
    
    -- [1.2] Variables de Estado
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- ¿Cómo está hoy?
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- ¿Cómo está el curso?
    DECLARE v_Curso_Activo INT DEFAULT 0;          -- Soft Delete
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;    -- ¿Ya fue evaluado?
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';
    
    -- [1.3] Variables para Lógica Híbrida (Solo usadas en Reinscripción)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Conteo_Sistema INT DEFAULT 0;
    DECLARE v_Conteo_Manual INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Cupo_Disponible INT DEFAULT 0;
    
    -- [1.4] Variables de Respuesta Dinámica
    DECLARE v_Mensaje_Final VARCHAR(255) DEFAULT '';
    DECLARE v_Accion_Final VARCHAR(50) DEFAULT '';
    
    -- [1.5] Constantes (Hardcoded IDs)
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;

    /* --------------------------------------------------------------------------------------------------
       MANEJO DE EXCEPCIONES
       -------------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'ERROR DE SISTEMA [500]: Fallo crítico al alternar el estado del participante.' AS Mensaje, 
               'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (FAIL-FAST)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR [400]: Ejecutor inválido.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    IF _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR [400]: Registro inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    IF TRIM(COALESCE(_Motivo_Cambio, '')) = '' 
		THEN
			SELECT 'ERROR [400]: El motivo es obligatorio para auditoría.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CONTEXTO (SNAPSHOT DE DATOS)
       Objetivo: Cargar toda la información necesaria para tomar la decisión (IF/ELSE).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Verificar Ejecutor
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR [403]: Ejecutor no válido.' AS Mensaje, 
			'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- 1.2 Cargar Datos del Alumno y Curso
    SELECT 
        COUNT(*),                               -- [0]
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus Actual
        `CP`.`Fk_Id_DatosCap`,                  -- [2] ID Detalle Curso
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [3] Nombre
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END, -- [4] ¿Ya tiene nota?
        `DC`.`Activo`,                          -- [5] Curso Activo?
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] Estatus Curso
        `DC`.`Fk_Id_Capacitacion`,              -- [7] ID Padre
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Manual Override
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual_Alumno,
        v_Id_Detalle_Curso,
        v_Nombre_Alumno,
        v_Tiene_Calificacion,
        v_Curso_Activo,
        v_Estatus_Curso,
        v_Id_Padre,
        v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- Validar existencia
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR [404]: El registro no existe.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- Validar Lista Negra de Cursos (Para cualquier operación)
    SELECT `Numero_Capacitacion`, 
		`Asistentes_Programados` 
    INTO v_Folio_Curso, 
		v_Cupo_Maximo
    FROM `Capacitaciones` 
	WHERE `Id_Capacitacion` = v_Id_Padre;

    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) THEN
        SELECT CONCAT('ERROR [409]: El curso "', v_Folio_Curso, '" está CANCELADO o ARCHIVADO. No se permiten cambios.') AS Mensaje, 
               'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: ÁRBOL DE DECISIÓN (TOGGLE LOGIC)
       Aquí es donde ocurre la magia. El sistema decide el camino basándose en v_Estatus_Actual_Alumno.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    IF v_Estatus_Actual_Alumno = c_ESTATUS_BAJA THEN
        
        /* ===============================================================================================
           RAMA A: REINSCRIBIR (El alumno estaba en BAJA -> Quiere volver a ENTRAR)
           Requiere: Validación de Cupo.
           =============================================================================================== */
        
        -- A.1 Validar Cupo Híbrido
        SELECT COUNT(*) INTO v_Conteo_Sistema 
        FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
          AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        IF v_Cupo_Disponible <= 0 
			THEN
				SELECT CONCAT('ERROR DE CUPO [409]: No se puede reactivar a "', v_Nombre_Alumno, '". Cupo Lleno.') AS Mensaje, 
					'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- A.2 Preparar Ejecución
        START TRANSACTION;
        UPDATE `Capacitaciones_Participantes`
        SET `Fk_Id_CatEstPart` = c_ESTATUS_INSCRITO,
            `Justificacion` = CONCAT('REACTIVADO [', DATE_FORMAT(NOW(), '%Y-%m-%d'), ']: ', _Motivo_Cambio),
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        SET v_Mensaje_Final = CONCAT('REINSCRIPCIÓN EXITOSA: "', v_Nombre_Alumno, '" está nuevamente activo.');
        SET v_Accion_Final = 'REINSCRITO';

    ELSE
        
        /* ===============================================================================================
           RAMA B: DAR DE BAJA (El alumno estaba ACTIVO -> Quiere SALIR)
           Requiere: Validación de Integridad (No tener calificación).
           =============================================================================================== */
        
        -- B.1 Validar que no tenga calificación
        IF v_Tiene_Calificacion = 1 
			THEN
				SELECT CONCAT('ERROR [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya tiene una calificación registrada.') AS Mensaje, 
                   'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- B.2 Preparar Ejecución
        START TRANSACTION;
        UPDATE `Capacitaciones_Participantes`
        SET `Fk_Id_CatEstPart` = c_ESTATUS_BAJA,
            `Justificacion` = CONCAT('BAJA [', DATE_FORMAT(NOW(), '%Y-%m-%d'), ']: ', _Motivo_Cambio),
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        SET v_Mensaje_Final = CONCAT('BAJA REGISTRADA: "', v_Nombre_Alumno, '" ha sido dado de baja.');
        SET v_Accion_Final = 'BAJA_EXITOSA';
        
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: RESPUESTA FINAL
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT v_Mensaje_Final AS Mensaje, v_Accion_Final AS Accion;

END$$
DELIMITER ;