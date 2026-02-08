/* ======================================================================================================
   PROCEDIMIENTO: SP_Reinscribir_Participante
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_Reinscribir_Participante
   - Clasificación:        Transacción de Recuperación (Recovery Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED
   - Perfil de Acceso:     Coordinador / Administrador
   - Dependencias:         Tablas: Usuarios, DatosCapacitaciones, Capacitaciones, Capacitaciones_Participantes.
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento gestiona la reactivación de un participante que previamente fue dado de BAJA.
   Su propósito es revertir una cancelación, ya sea por error administrativo o porque el alumno
   finalmente sí pudo asistir.
   
   [REGLA DE RE-INGRESO]:
   La reinscripción se trata como una "Nueva Inscripción" en términos de validación de cupo.
   Aunque el registro ya existe físicamente, al estar en BAJA liberó su asiento. Para volver a entrar,
   debe competir por el cupo disponible nuevamente bajo la lógica híbrida.
   
   [AUDITORÍA FORENSE]:
   Al reactivar, se sobrescribe el campo `Justificacion` con el motivo de la reactivación, 
   dejando rastro de quién y por qué autorizó el reingreso.

   ------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE VALIDACIÓN
   ------------------------------------------------------------------------------------------------------
   1. Integridad: El registro debe existir y estar en estado BAJA (5).
   2. Contexto: El curso no debe estar CANCELADO (8) ni ARCHIVADO (10).
   3. Capacidad: Debe existir cupo disponible (Meta - Max(Sistema, Manual)).
   4. Ejecución: Update atómico del estatus a INSCRITO (1).

   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Reinscribir_Participante`$$

CREATE PROCEDURE `SP_Reinscribir_Participante`(
    /* --------------------------------------------------------------------------------------------------
       DEFINICIÓN DE PARÁMETROS DE ENTRADA
       -------------------------------------------------------------------------------------------------- */
    IN _Id_Usuario_Ejecutor INT,       -- Admin que autoriza
    IN _Id_Registro_Participante INT,  -- ID Primario de la tabla de relación (Id_CapPart)
    IN _Motivo_Reinscripcion VARCHAR(250) -- Justificación obligatoria
)
ProcReinsPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: DECLARACIÓN DE VARIABLES Y MEMORIA
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Validación
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;
    DECLARE v_Id_Usuario_Alumno INT DEFAULT 0;
    
    -- [1.2] Variables de Contexto (Estado Actual)
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';
    DECLARE v_Estatus_Curso INT DEFAULT 0; -- ID del estatus del curso (1-10)
    DECLARE v_Curso_Activo INT DEFAULT 0;  -- Soft Delete Check
    DECLARE v_Id_Padre INT DEFAULT 0;
    
    -- [1.3] Variables de Cupo Híbrido
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Conteo_Sistema INT DEFAULT 0;
    DECLARE v_Conteo_Manual INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Cupo_Disponible INT DEFAULT 0;
    
    -- [1.4] Constantes de Negocio (Hardcoded)
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- [1.5] Constantes de Lista Negra (Cursos Inoperables)
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;

    /* --------------------------------------------------------------------------------------------------
       MANEJO DE EXCEPCIONES (FAIL-SAFE)
       -------------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'ERROR DE SISTEMA [500]: Fallo interno al procesar la reinscripción.' AS Mensaje, 
               'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (FAIL-FAST)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: Ejecutor inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcReinsPart; 
    END IF;
    
    IF _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: ID de registro inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcReinsPart; 
    END IF;
    
    IF TRIM(COALESCE(_Motivo_Reinscripcion, '')) = '' 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El motivo de reinscripción es obligatorio para auditoría.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcReinsPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE IDENTIDAD Y EXISTENCIA
       Objetivo: Asegurar que los actores y el registro objetivo existen.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Validar Ejecutor
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
		AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: Ejecutor no válido.' AS Mensaje,
			'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcReinsPart; 
    END IF;
    
    -- 1.2 Cargar Datos del Registro Objetivo (Snapshot)
    -- Obtenemos toda la info necesaria para validar reglas de negocio en un solo paso.
    SELECT 
        COUNT(*),                               -- [0] Existe?
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus actual del alumno
        `CP`.`Fk_Id_DatosCap`,                  -- [2] ID del Curso (Hijo)
        `CP`.`Fk_Id_Usuario`,                   -- [3] ID del Alumno
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [4] Nombre legible
        `DC`.`Activo`,                          -- [5] Soft Delete del Curso
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] Estatus Operativo del Curso
        `DC`.`Fk_Id_Capacitacion`,              -- [7] ID Padre
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Conteo Manual (Para cupo híbrido)
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual_Alumno,
        v_Id_Detalle_Curso,
        v_Id_Usuario_Alumno,
        v_Nombre_Alumno,
        v_Curso_Activo,
        v_Estatus_Curso,
        v_Id_Padre,
        v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- Validación de Existencia
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR [404]: El registro de inscripción no existe.' AS Mensaje, 
			'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcReinsPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DE REGLAS DE NEGOCIO (BUSINESS RULES)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Regla 2.1: Solo se puede reinscribir lo que está dado de baja.
    IF v_Estatus_Actual_Alumno != c_ESTATUS_BAJA 
		THEN
			SELECT CONCAT('AVISO: El alumno "', v_Nombre_Alumno, '" NO está dado de baja (Estatus: ', v_Estatus_Actual_Alumno, '). No requiere acción.') AS Mensaje, 
               'SIN_CAMBIOS' AS Accion; 
        LEAVE ProcReinsPart;
    END IF;
    
    -- Regla 2.2: El curso no debe estar eliminado lógicamente.
    IF v_Curso_Activo = 0 
		THEN
			SELECT 'ERROR DE NEGOCIO [409]: El curso fue eliminado o archivado. No se pueden reactivar inscripciones.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion; 
        LEAVE ProcReinsPart;
    END IF;
    
    -- Regla 2.3: Obtener Metadatos del Padre (Folio y Cupo Máximo)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo
    FROM `Capacitaciones` WHERE `Id_Capacitacion` = v_Id_Padre;
    
    -- Regla 2.4: Lista Negra de Estatus (Permisividad Administrativa)
    -- Permitimos reinscribir en cursos "Finalizados" (para corrección), pero NO en "Cancelados".
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT CONCAT('ERROR [409]: El curso "', v_Folio_Curso, '" está CANCELADO o ARCHIVADO. Operación prohibida.') AS Mensaje, 
				   'ESTATUS_PROHIBIDO' AS Accion; 
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE CUPO (LÓGICA HÍBRIDA)
       Objetivo: Verificar si al "revivir" a este alumno, cabemos en el salón.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 3.1 Contar ocupados actuales (Excluyendo al que estamos por revivir, que ya está excluido por ser BAJA)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- 3.2 Aplicar Factor Pesimista (Manual vs Sistema)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
    
    -- 3.3 Calcular Disponibilidad
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- 3.4 Veredicto
    IF v_Cupo_Disponible <= 0 
		THEN
			SELECT CONCAT('ERROR DE CUPO [409]: No hay espacio para reinscribir a "', v_Nombre_Alumno, '". Cupo: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo) AS Mensaje, 
				   'CUPO_LLENO' AS Accion; 
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: EJECUCIÓN (UPDATE CON AUDITORÍA)
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_CatEstPart` = c_ESTATUS_INSCRITO,  -- Resucita a estatus 1
        
        -- [AUDITORÍA]: Concatenamos la razón de la reactivación
        `Justificacion` = CONCAT('REINSCRIPCIÓN [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ', _Motivo_Reinscripcion),
        
        -- [TRAZABILIDAD]: Actualizamos quién hizo el cambio
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('REINSCRIPCIÓN EXITOSA: "', v_Nombre_Alumno, '" reactivado en "', v_Folio_Curso, '".') AS Mensaje, 
        'REINSCRITO' AS Accion;

END$$
DELIMITER ;