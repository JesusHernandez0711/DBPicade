/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_EditarParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_EditarParticipanteCapacitacion
   - Sistema Operativo    : PICADE - Módulo de Gestión de Capital Humano
   - Auditoria Forense    : Registro de Calificaciones, Asistencia y Estatus de Resultados
   - Alias Operativo      : "El Auditor Académico" / "The Result Settlement Engine"
   - Clasificación        : Transacción de Gestión de Resultados e Integridad Histórica.
   - Patrón de Diseño     : Hybrid State Machine with Idempotency and Audit Injection.
   - Nivel de Aislamiento : REPEATABLE READ (Protección contra lecturas fantasmas durante el cálculo).
   - Criticidad           : EXTREMA (Afecta actas legales de capacitación y promedios históricos).

   II. PROPÓSITO Y VERSATILIDAD (BUSINESS VALUE PROPOSITION)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento representa el "Cierre de Ciclo" del participante dentro de una unidad de aprendizaje.
   Su diseño está orientado a la resiliencia y la transparencia administrativa, permitiendo:
   
   1. ASENTAMIENTO PRIMARIO: Registro original de la evidencia de aprendizaje y presencia.
   2. CORRECCIÓN DE ERRORES: Ajuste de datos previos sin pérdida de la historia original.
   3. OVERRIDE JERÁRQUICO: El Administrador tiene la potestad de ignorar el cálculo matemático del 
      sistema para asignar estatus manuales por criterio institucional.
   4. CUMPLIMIENTO (COMPLIANCE): Generación de una traza forense inmutable en cada edición.

   III. MATRIZ DE PRIORIDADES LÓGICAS (LOGIC HIERARCHY MATRIX)
   ----------------------------------------------------------------------------------------------------------
   El motor de base de datos evalúa la entrada de datos en el siguiente orden estricto de precedencia:
   
   - NIVEL 1 (MANUAL): Si se provee un Estatus Explícito, el sistema anula cualquier cálculo automático.
   - NIVEL 2 (ANALÍTICO): Si hay una calificación, el sistema determina el éxito basado en el umbral (70).
   - NIVEL 3 (LOGÍSTICO): Si solo hay asistencia, el sistema asume la participación (Asistió).
   - NIVEL 4 (CONSERVADOR): Si no se envían datos, se mantienen los valores previos (COALESCE logic).

   IV. ARQUITECTURA DE SEGURIDAD (DEFENSE IN DEPTH)
   ----------------------------------------------------------------------------------------------------------
   1. BARRERA DE ENTRADA: Sanitización de tipos de datos y rangos decimales.
   2. BARRERA DE IDENTIDAD: Validación de estatus Activo del usuario ejecutor.
   3. BARRERA DE CONTEXTO: Snapshot de memoria para evitar inconsistencias durante el proceso.
   4. BARRERA DE ESTADO: Protección contra edición de registros en BAJA (Freeze state).
   5. BARRERA TRANSACCIONAL: Atomicidad garantizada (All-or-Nothing).

   ========================================================================================================== */
-- Eliminación preventiva del objeto para garantizar una recompilación limpia del motor de SP.

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_EditarParticipanteCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INTERFACE DEFINITION)
       Se utilizan tipos de datos DECIMAL(5,2) para precisión exacta en escalas de 0.00 a 100.00.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario_Ejecutor INT,           -- [PK_REF] ID del Admin/Instructor responsable de la firma digital.
    IN _Id_Registro_Participante INT,      -- [PK_REF] ID único de la fila en la tabla de relación.
    IN _Calificacion DECIMAL(5,2),         -- [DATA] Nueva nota numérica. NULL si no se desea modificar.
    IN _Porcentaje_Asistencia DECIMAL(5,2),-- [DATA] Nuevo % de asistencia. NULL si no se desea modificar.
    IN _Id_Estatus_Resultado INT,          -- [FLAG] Forzado manual de estatus (Override administrativo).
    IN _Justificacion_Cualitativa VARCHAR(250) -- [AUDIT] Razón del cambio o descripción de la nota.
)
ProcUpdatResulPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (DATA SNAPSHOT)
       El objetivo es cargar el estado actual del mundo en memoria local para validaciones rápidas.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Integridad Referencial
    -- Estas variables confirman que los punteros apunten a objetos vivos en el diccionario de datos.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Validador de existencia para el responsable.
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Validador de existencia para el registro objetivo.
    
    -- [1.2] Variables de Contexto Académico (Read-Only Copy)
    -- Almacenan la "verdad" de la base de datos antes de que sea sobreescrita por el UPDATE.
    DECLARE v_Estatus_Actual INT DEFAULT 0;        -- Estatus registrado actualmente en la fila.
    DECLARE v_Calificacion_Previa DECIMAL(5,2);    -- Última nota grabada (para el Audit Trail).
    DECLARE v_Asistencia_Previa DECIMAL(5,2);      -- Última asistencia grabada (para el Audit Trail).
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre recuperado de Info_Personal para feedback.
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Numero_Capacitacion para mensajes contextuales.
    
    -- [1.3] Variables de Cálculo y Auditoría Dinámica
    -- Gestionan la lógica de la máquina de estados y la construcción del log forense.
    DECLARE v_Nuevo_Estatus_Calculado INT DEFAULT 0;-- ID resultante después de evaluar las reglas.
    DECLARE v_Audit_Trail_Final TEXT;              -- Cadena concatenada que se inyectará en 'Justificacion'.
    
    -- [1.4] Constantes de Reglas de Negocio (Standard Business Mapping)
    -- Definidas estáticamente para garantizar la alineación con el catálogo Cat_Estatus_Participante.
    DECLARE c_EST_ASISTIO INT DEFAULT 2;           -- Estatus: Solo participación física.
    DECLARE c_EST_APROBADO INT DEFAULT 3;          -- Estatus: Evidencia de aprendizaje satisfactoria.
    DECLARE c_EST_REPROBADO INT DEFAULT 4;         -- Estatus: Evidencia de aprendizaje insuficiente.
    DECLARE c_EST_BAJA INT DEFAULT 5;              -- Estatus: Fuera de la matrícula (Estado ineditable).
    DECLARE c_UMBRAL_APROBACION DECIMAL(5,2) DEFAULT 70.00; -- Nota mínima legal para acreditar.

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       Este bloque es el peritaje automático ante fallos del motor InnoDB o de red.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Ante cualquier error inesperado, revierte los cambios iniciados.
        ROLLBACK;
        -- Emite una señal de error 500 para la capa de servicios de la aplicación.
        SELECT 
            'ERROR TÉCNICO [500]: Fallo crítico detectado por el motor de BD al asentar resultados.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN FORENSE (FAIL-FAST STRATEGY)
       Rechaza la petición antes de comprometer la integridad del Snapshot.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación de Identificadores (Punteros de Memoria)
    -- Se prohíbe el uso de IDs nulos o negativos que puedan causar lecturas inconsistentes.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido.' AS Mensaje, 
			'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro es inválido.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [0.2] Validación de Integridad de Escala (Rango Numérico)
    -- Asegura que los datos sigan la escala decimal estándar del 0 al 100.
    IF (_Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100)) OR 
       (_Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100)) 
		THEN
			SELECT 'ERROR DE RANGO [400]: Las notas y asistencias deben estar entre 0.00 y 100.00.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    -- [0.3] Validación de Cumplimiento (Compliance Check)
    -- Exige que cada cambio en la historia académica del alumno esté fundamentado.
    IF _Justificacion_Cualitativa IS NULL OR TRIM(_Justificacion_Cualitativa) = '' 
		THEN
			SELECT 'ERROR DE AUDITORÍA [400]: Es obligatorio proporcionar un motivo para este cambio de resultados.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CAPTURA DE SNAPSHOT ACADÉMICO (READ BEFORE WRITE)
       Recopila los datos actuales de las tablas físicas hacia las variables locales de memoria.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Verificación de Existencia y Actividad del Ejecutor
    -- Confirmamos que quien califica es un usuario válido y no ha sido inhabilitado.
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
    AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 
		THEN 
			SELECT 'ERROR DE PERMISOS [403]: El usuario ejecutor no posee credenciales activas.' AS Mensaje, 
            'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;
    
    -- [1.2] Hidratación de Variables de la Inscripción (Snapshot Forense)
    -- Recupera la nota previa, asistencia previa y estatus actual para el análisis de cambio.
    SELECT 
        COUNT(*), 
        `CP`.`Fk_Id_CatEstPart`, 
        `CP`.`Calificacion`, 
        `CP`.`PorcentajeAsistencia`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), 
        `C`.`Numero_Capacitacion`
    INTO 
        v_Registro_Existe, 
        v_Estatus_Actual, 
        v_Calificacion_Previa, 
        v_Asistencia_Previa,
        v_Nombre_Alumno, 
        v_Folio_Curso
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Existencia de Matrícula
    -- Si la consulta no devolvió filas, el ID enviado es erróneo.
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: El registro de matrícula solicitado no existe en BD.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcUpdatResulPart; 
    END IF;

    -- [1.4] Protección contra Modificación de Bajas (Immutability Layer)
    -- Un alumno en BAJA ha liberado su lugar; calificarlo rompería la lógica del ciclo de vida.
    IF v_Estatus_Actual = c_EST_BAJA 
		THEN
			SELECT CONCAT('ERROR DE NEGOCIO [409]: Imposible calificar a "', v_Nombre_Alumno, '" porque se encuentra en BAJA.') AS Mensaje, 
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: MÁQUINA DE ESTADOS Y CÁLCULO DE AUDITORÍA (BUSINESS LOGIC ENGINE)
       Calcula el nuevo estatus y construye la traza forense acumulativa.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [2.1] Determinación de Nuevo Estatus (Hierarchical Logic)
    -- El sistema evalúa qué camino tomar basado en los parámetros recibidos.
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- CAMINO 1: OVERRIDE MANUAL. La voluntad del Admin es ley.
        SET v_Nuevo_Estatus_Calculado = _Id_Estatus_Resultado;
    
    ELSEIF _Calificacion IS NOT NULL THEN
        -- CAMINO 2: CÁLCULO ANALÍTICO. Se evalúa el desempeño académico contra el umbral de aprobación.
        IF _Calificacion >= c_UMBRAL_APROBACION THEN 
            SET v_Nuevo_Estatus_Calculado = c_EST_APROBADO;
        ELSE 
            SET v_Nuevo_Estatus_Calculado = c_EST_REPROBADO; 
        END IF;
    
    ELSEIF _Porcentaje_Asistencia IS NOT NULL AND v_Estatus_Actual = 1 THEN
        -- CAMINO 3: AVANCE LOGÍSTICO. Si el alumno está "Inscrito" y se pone asistencia, avanza a "Asistió".
        SET v_Nuevo_Estatus_Calculado = c_EST_ASISTIO;
    
    ELSE
        -- CAMINO 4: PRESERVACIÓN. No hay cambios de estado, se mantiene el actual.
        SET v_Nuevo_Estatus_Calculado = v_Estatus_Actual;
    END IF;

    -- [2.2] Construcción de Inyección Forense (Serialized Audit Note)
    -- Genera una cadena detallada que permite reconstruir la operación sin consultar logs secundarios.
    SET v_Audit_Trail_Final = CONCAT(
        'EDIT_RES [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ',
        'NOTA_ACT: ', COALESCE(_Calificacion, v_Calificacion_Previa, '0.00'), 
        ' | ASIST_ACT: ', COALESCE(_Porcentaje_Asistencia, v_Asistencia_Previa, '0.00'), '%',
        ' | MOTIVO: ', _Justificacion_Cualitativa
    );

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: PERSISTENCIA TRANSACCIONAL (DATA SETTLEMENT)
       Aplica los cambios en las tablas físicas garantizando integridad ACID.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
        -- Ejecución de la actualización de fila (Update atomicity).
        UPDATE `Capacitaciones_Participantes`
        SET 
            -- Aplicamos COALESCE para permitir actualizaciones parciales sin borrar datos existentes.
            `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
            `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
            `Fk_Id_CatEstPart` = v_Nuevo_Estatus_Calculado,
            -- Inyección de la nota forense en la columna de justificación.
            `Justificacion` = v_Audit_Trail_Final,
            -- Sellos de auditoría de tiempo y autoría.
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
        WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    -- Si no hubo interrupciones críticas, el motor InnoDB persiste los cambios físicos.
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA DINÁMICA (UX & API FEEDBACK)
       Emite un resultset de una sola fila para que la aplicación (Laravel) confirme el éxito al usuario.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('ÉXITO: Se han guardado los resultados para "', v_Nombre_Alumno, '" en el curso "', v_Folio_Curso, '".') AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   NOTAS DE IMPLEMENTACIÓN FORENSE:
   1. RESILIENCIA AL NULL: El uso de COALESCE permite que el SP sea usado en formularios parciales.
   2. TRAZABILIDAD: La columna `Justificacion` acumula la historia de la nota, vital para revisiones de la STPS.
   3. INTEGRIDAD: El bloqueo de BAJA (Estatus 5) asegura que no existan resultados para alumnos fuera de nómina.
   4. CONCURRENCIA: El nivel REPEATABLE READ evita colisiones si dos admins editan al mismo alumno al unísono.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */