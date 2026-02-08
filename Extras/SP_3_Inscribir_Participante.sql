/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_RegistrarParticipanteCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   SECCIÓN 1: FICHA TÉCNICA DEL ARTEFACTO (ARTIFACT DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre del Objeto:    SP_RegistrarParticipanteCapacitacion
   - Tipo de Objeto:       Rutina Almacenada (Stored Procedure)
   - Clasificación:        Transacción de Escritura Crítica (Critical Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Perfil de Ejecución:  Privilegiado (Administrador / Coordinador)
   
   SECCIÓN 2: MAPEO DE DEPENDENCIAS (DEPENDENCY MAPPING)
   ----------------------------------------------------------------------------------------------------------
   A. Tablas de Lectura (Read Access):
      1. Usuarios (Validación de identidad y estatus)
      2. DatosCapacitaciones (Validación de existencia de curso y configuración manual)
      3. Capacitaciones (Lectura de Meta/Cupo Máximo)
      4. Cat_Estatus_Capacitacion (Validación de reglas de negocio por estatus)
   
   B. Tablas de Escritura (Write Access):
      1. Capacitaciones_Participantes (Inserción del registro de inscripción)
   
   SECCIÓN 3: ESPECIFICACIÓN DE LA LÓGICA DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ----------------------------------------------------------------------------------------------------------
   OBJETIVO PRIMARIO:
   Registrar la relación entre un Usuario (Alumno) y una Capacitación (Curso), garantizando la integridad
   referencial, la unicidad del registro y el cumplimiento de las reglas de cupo.

   REGLA DE SUPER-USUARIO (ADMIN OVERRIDE):
   A diferencia del proceso de auto-inscripción, este procedimiento permite a un administrador realizar
   "Correcciones Históricas". 
   - PERMITIDO: Inscribir en cursos "Finalizados", "En Evaluación" o "En Curso" (para regularizar).
   - DENEGADO: Inscribir en cursos "Cancelados" (8) o "Archivados" (10), ya que son expedientes muertos.

   ALGORITMO DE CUPO HÍBRIDO (HYBRID CAPACITY ALGORITHM):
   Para determinar si existe espacio, el sistema no confía ciegamente en el conteo de filas.
   Se utiliza una estrategia "Pesimista" para evitar el sobrecupo físico:
     Paso A: Calcular ocupación del sistema = COUNT(*) WHERE Estatus != BAJA.
     Paso B: Leer ocupación manual = DatosCapacitaciones.AsistentesReales (Input humano).
     Paso C: Determinar Ocupación Efectiva = GREATEST(Paso A, Paso B).
     Paso D: Disponibilidad = Meta_Programada - Ocupación_Efectiva.
   
   Si Disponibilidad <= 0, la transacción se rechaza, protegiendo la integridad del aula.

   ----------------------------------------------------------------------------------------------------------
   SECCIÓN 4: CÓDIGOS DE RETORNO Y MANEJO DE ERRORES (RETURN CODES)
   ----------------------------------------------------------------------------------------------------------
   [400] ERROR_ENTRADA:      Parámetros nulos o iguales a cero.
   [403] ACCESO_DENEGADO:    El ejecutor no tiene permisos o el usuario destino está inactivo.
   [404] RECURSO_NO_ENCO...: El curso o el usuario no existen en la base de datos.
   [409] CONFLICTO_ESTADO:   El curso fue borrado lógicamente (Soft Delete).
   [409] ESTATUS_PROHIBIDO:  Intento de inscripción en curso Cancelado o Archivado.
   [409] DUPLICADO:          El usuario ya tiene un asiento en este curso (Idempotencia).
   [409] CUPO_LLENO:         No hay asientos disponibles según la lógica híbrida.
   [500] ERROR_TECNICO:      Fallo de SQL (Deadlock, Constraint Violation, Timeout).
   
   ========================================================================================================== */
-- Verificación previa para limpieza de entorno (Drop if exists pattern)

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarParticipanteCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarParticipanteCapacitacion`(
    /* ------------------------------------------------------------------------------------------------------
       DEFINICIÓN DE PARÁMETROS DE ENTRADA (INPUT INTERFACE)
       ------------------------------------------------------------------------------------------------------ */
    IN _Id_Usuario_Ejecutor INT,      -- [REQUIRED]: ID del usuario Admin/Coord que ejecuta la acción.
    IN _Id_Detalle_Capacitacion INT,  -- [REQUIRED]: ID único de la versión del curso (Tabla Hija).
    IN _Id_Usuario_Participante INT   -- [REQUIRED]: ID del usuario Alumno que será inscrito.
)
ProcInsPart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE MEMORIA Y VARIABLES (MEMORY MANAGEMENT)
       Nota Técnica: Se inicializan todas las variables por defecto para evitar valores NULL
       que puedan romper operaciones matemáticas o comparaciones lógicas.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- 1.1 Variables de Verificación de Entidades (Flags de Existencia)
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Semáforo para el admin
    DECLARE v_Participante_Existe INT DEFAULT 0;   -- Semáforo para el alumno
    DECLARE v_Participante_Activo INT DEFAULT 0;   -- Estado lógico del alumno (1=Activo)
    
    -- 1.2 Variables de Contexto de la Capacitación (Snapshot de Datos)
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;   -- Semáforo de existencia física
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;   -- Semáforo de existencia lógica (Soft Delete)
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0; -- ID de la tabla padre (Temario/Meta)
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Identificador humano (para mensajes de error)
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- ID del estatus operativo actual del curso
    
    -- 1.3 Variables para el Algoritmo de Cupo Híbrido (Capacity Logic)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Límite duro definido en la planeación
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Cantidad de registros en DB (Automático)
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Cantidad forzada por el coordinador (Manual)
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- Resultado de la función GREATEST()
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Resultado final (Meta - Ocupados)
    
    -- 1.4 Variables de Control de Flujo y Resultado
    DECLARE v_Ya_Inscrito INT DEFAULT 0;           -- Bandera para detección de duplicados
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;     -- Almacena el ID generado tras el INSERT (Identity)
    
    -- 1.5 Constantes de Estado de Participante (Hardcoded Business Rules)
    -- Se definen para evitar "números mágicos" en el código y facilitar mantenimiento.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;      -- El usuario entra con estatus "Inscrito"
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- Estatus "Baja" libera el cupo
    
    -- 1.6 Constantes de Lista Negra de Cursos (Admin Blacklist)
    -- Estos son los únicos estados donde el Admin NO puede operar.
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;       -- Un curso cancelado es inoperable
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;      -- Un curso archivado es de solo lectura

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES Y ATOMICIDAD (ACID COMPLIANCE)
       Objetivo: Implementar un mecanismo de seguridad (Fail-Safe).
       Si ocurre cualquier error SQL crítico durante la ejecución, se revierte todo.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [CRÍTICO]: Revertir cualquier cambio pendiente en la transacción actual.
        ROLLBACK;
        
        -- Retornar mensaje estandarizado de error 500 al cliente.
        SELECT 
            'ERROR DE SISTEMA [500]: Fallo interno crítico durante la transacción de inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (INPUT SANITIZATION - FAIL FAST)
       Objetivo: Validar la integridad estructural de los datos antes de procesar lógica de negocio.
       Esto ahorra recursos de CPU y Base de Datos al rechazar peticiones mal formadas inmediatamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Integridad del Ejecutor
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.2: Integridad del Recurso (Curso)
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;
    
    -- Validación 0.3: Integridad del Destinatario (Participante)
    IF _Id_Usuario_Participante IS NULL OR _Id_Usuario_Participante <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El ID del Participante es obligatorio.' AS Mensaje, 
				   'VALIDACION_FALLIDA' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart; -- Terminación inmediata
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CREDENCIALES DEL EJECUTOR (SECURITY LAYER)
       Objetivo: Asegurar que la solicitud proviene de un actor válido en el sistema.
       No verificamos roles aquí (eso es capa de aplicación), pero sí existencia y actividad.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
      AND `Activo` = 1; -- Solo usuarios activos pueden ejecutar acciones
    
    IF v_Ejecutor_Existe = 0 
		THEN
			SELECT 'ERROR DE SEGURIDAD [403]: El Usuario Ejecutor no es válido o está inactivo.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: VERIFICACIÓN DE ELEGIBILIDAD DEL PARTICIPANTE (TARGET VALIDATION)
       Objetivo: Asegurar la integridad referencial del alumno destino.
       Regla de Negocio: No se puede inscribir a un usuario que ha sido dado de baja administrativamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*), `Activo` 
    INTO v_Participante_Existe, v_Participante_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    -- Validación 2.1: Existencia Física del Registro
    IF v_Participante_Existe = 0 
		THEN
			SELECT 'ERROR DE INTEGRIDAD [404]: El usuario a inscribir no existe en el sistema.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validación 2.2: Estado Operativo del Usuario (Soft Delete Check)
    IF v_Participante_Activo = 0 
		THEN
			SELECT 'ERROR DE LÓGICA [409]: El usuario está INACTIVO (Baja Administrativa). No puede ser inscrito.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: CARGA DE CONTEXTO Y VALIDACIÓN DE ESTADO DEL CURSO (CONTEXT AWARENESS)
       Objetivo: Recuperar todos los metadatos necesarios del curso en una sola operación optimizada.
       Aquí se aplica la regla de negocio de "Corrección Histórica" para Administradores.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*),                             -- [0] Existe el registro?
        COALESCE(`DC`.`Activo`, 0),           -- [1] Está borrado lógicamente?
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID del Padre (Para buscar cupo máximo)
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Estatus Operativo (1-10)
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] Asistentes Manuales (Input de Coordinador)
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 3.1: Integridad Referencial del Curso
    IF v_Capacitacion_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: La capacitación indicada no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    -- Validación 3.2: Integridad Lógica (Curso eliminado)
    IF v_Capacitacion_Activa = 0 
		THEN 
			SELECT 'ERROR DE LÓGICA [409]: Esta versión del curso está ARCHIVADA o eliminada.' AS Mensaje, 
				   'CONFLICTO_ESTADO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;
    
    -- [RECUPERACIÓN DE METADATA DEL PADRE]
    -- Obtenemos el folio para mensajes y el cupo programado (Meta) para los cálculos.
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    /* ------------------------------------------------------------------------------------------------------
       [VALIDACIÓN DE LISTA NEGRA DE ESTATUS - BUSINESS RULE ENFORCEMENT]
       Aquí aplicamos la lógica específica para Admins. 
       A diferencia del usuario normal, el Admin PUEDE inscribir en cursos pasados (Finalizados, En Evaluación).
       
       SOLO se bloquea si el curso está:
       - CANCELADO (ID 8): Porque nunca ocurrió.
       - CERRADO/ARCHIVADO (ID 10): Porque el expediente administrativo ya se cerró.
       ------------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT 
				CONCAT('ERROR DE NEGOCIO [409]: No se puede modificar la lista de asistentes. El curso "', v_Folio_Curso, 
					   '" se encuentra en un estatus inoperable (ID: ', v_Estatus_Curso, ').') AS Mensaje, 
				'ESTATUS_PROHIBIDO' AS Accion, 
				NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE UNICIDAD (IDEMPOTENCY CHECK)
       Objetivo: Prevenir registros duplicados. Un alumno no puede ocupar dos asientos en el mismo curso.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Ya_Inscrito > 0 
		THEN 
			SELECT CONCAT('AVISO DE NEGOCIO: El usuario ya se encuentra registrado en el curso "', v_Folio_Curso, '".') AS Mensaje, 
				   'DUPLICADO' AS Accion, 
				   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: VALIDACIÓN DE CAPACIDAD (ALGORITMO DE CUPO HÍBRIDO)
       Objetivo: Determinar la disponibilidad real de asientos utilizando lógica pesimista.
       Nota: Incluso en correcciones históricas, respetamos la capacidad máxima del aula para no 
       generar inconsistencias en los reportes de ocupación.
       
       Fórmula: Disponible = Meta - MAX(Conteo_Sistema, Conteo_Manual)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Paso 5.1: Contar ocupación real en sistema (Excluyendo bajas)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 5.2: Aplicar Regla del Máximo (Sistema vs Manual)
    -- Si el coordinador puso "30" manuales, y hay 5 en sistema, tomamos 30.
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 5.3: Calcular Delta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 5.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN 
			SELECT CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO en "', v_Folio_Curso, '". Ocupados: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo, '.') AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
                   NULL AS Id_Registro_Participante; 
        LEAVE ProcInsPart; 
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 6: EJECUCIÓN TRANSACCIONAL (ACID COMMIT)
       Objetivo: Persistir el cambio en la base de datos de manera atómica.
       Aquí se abre la transacción y se bloquean los recursos necesarios para la escritura.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`,            -- FK: Curso
        `Fk_Id_Usuario`,             -- FK: Alumno
        `Fk_Id_CatEstPart`,          -- FK: Estatus Inicial (1)
        `Calificacion`,              -- NULL por defecto
        `PorcentajeAsistencia`,      -- NULL por defecto
        `created_at`,                -- Auditoría: Creación
        `updated_at`,                -- Auditoría: Última Modificación
        `Fk_Id_Usuario_Created_By`,  -- Auditoría: Responsable (Admin)
        `Fk_Id_Usuario_Updated_By`   -- Auditoría: Responsable (Admin)
    ) VALUES (
        _Id_Detalle_Capacitacion,
        _Id_Usuario_Participante,
        c_ESTATUS_INSCRITO,          -- Inicializa como "INSCRITO"
        NULL, 
        NULL,
        NOW(), 
        NOW(), 
        _Id_Usuario_Ejecutor,        -- El Admin es el creador
        _Id_Usuario_Ejecutor
    );
    
    -- Recuperar el ID autogenerado para confirmación
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT; -- Confirmación definitiva en disco

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 7: RESPUESTA EXITOSA Y FEEDBACK (SUCCESS RESPONSE)
       Objetivo: Informar al cliente que la operación fue exitosa y retornar metadatos útiles.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('INSCRIPCIÓN EXITOSA: Usuario agregado a "', v_Folio_Curso, '". Lugares restantes: ', (v_Cupo_Disponible - 1)) AS Mensaje, 
        'INSCRITO' AS Accion, 
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$

DELIMITER ;

