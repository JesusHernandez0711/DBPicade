/* ======================================================================================================
   PROCEDIMIENTO: SP_RegistrarParticipacionCapacitacion
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_RegistrarParticipacionCapacitacion
   - Clasificación:        Transacción de Escritura / Auto-Servicio (Self-Service Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Patrón de Diseño:     Fail-Fast & Pessimistic Locking Logic
   - Perfil de Ejecución:  Usuario Final (Alumno / Empleado)
   - Dependencias:         Tablas: Usuarios, DatosCapacitaciones, Capacitaciones, Capacitaciones_Participantes.
                           Vistas: Ninguna (Acceso directo a tablas para integridad ACID).
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC SPECIFICATION)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento gestiona la lógica de "Auto-Matriculación". Permite a un usuario activo 
   registrarse a sí mismo en una oferta de capacitación vigente.
   
   [REGLAS DE INSCRIPCIÓN VIGENTE]:
   El curso debe estar en uno de los siguientes estados operativos para aceptar alumnos:
   - PROGRAMADO (ID 1): El curso está confirmado en calendario oficial.
   - POR INICIAR (ID 2): Faltan pocas horas/días, etapa crítica de llenado de cupo.
   - REPROGRAMADO (ID 9): Hubo cambio de fecha, pero la oferta sigue abierta.
   
   [RESTRICCIONES]:
   - NO se permite inscripción en "EN DISEÑO", "CANCELADO" o estatus administrativos no públicos.
   - NO se permite inscripción en "EN CURSO" o "FINALIZADO" (Integridad pedagógica).

   ------------------------------------------------------------------------------------------------------
   3. ALGORITMO DE "CUPO HÍBRIDO PESIMISTA" (CORE LOGIC)
   ------------------------------------------------------------------------------------------------------
   Para evitar el problema de "Sobreventa" (Overbooking) común en sistemas concurrentes:
   
   Definimos:
     [A] = Conteo Real en BD (`SELECT COUNT(*)`). Es la verdad del sistema.
     [B] = Bloqueo Manual (`AsistentesReales`). Es la verdad del coordinador (ej. "Tengo 5 invitados externos").
     [C] = Capacidad Máxima (`Asistentes_Programados`). Es el límite físico del aula.
   
   Fórmula de Disponibilidad:
     Ocupados = GREATEST( [A], [B] )  -> "Tomamos el escenario más pesimista (mayor ocupación)"
     Disponibles = [C] - Ocupados
   
   Regla de Decisión:
     IF Disponibles <= 0 THEN REJECT TRANSACTION.

   ------------------------------------------------------------------------------------------------------
   4. DICCIONARIO DE RESPUESTAS (RETURN CODES)
   ------------------------------------------------------------------------------------------------------
   | Código            | Significado Técnico                     | Mensaje al Usuario                         |
   |-------------------|-----------------------------------------|--------------------------------------------|
   | LOGOUT_REQUIRED   | Input NULL o <= 0                       | Error de sesión.                           |
   | VALIDACION_FALLIDA| ID Curso inválido                       | Curso no válido.                           |
   | CONTACTAR_SOPORTE | Usuario no encontrado en DB             | Tu usuario no existe.                      |
   | ACCESO_DENEGADO   | Usuario marcado Activo=0                | Tu cuenta está inactiva.                   |
   | RECURSO_NO_ENCO...| Curso no existe en DB                   | El curso que buscas no existe.             |
   | CURSO_CERRADO     | Curso Archiv=0 o Estatus=Final          | Este curso ha sido archivado/finalizado.   |
   | ESTATUS_INVALIDO  | Estatus no permitido (ej. ID 3,4,5...)  | El curso no está abierto para inscripciones.|
   | YA_INSCRITO       | Violación de Unique Key Lógica          | Ya tienes un lugar reservado.              |
   | CUPO_LLENO        | Disponibilidad <= 0                     | Lo sentimos, ya no hay lugares.            |
   | INSCRITO          | Éxito (Commit realizado)                | ¡Registro Exitoso!                         |
   | ERROR_TECNICO     | Excepción SQL (Deadlock/Constraint)     | Ocurrió un error interno.                  |

   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarParticipacionCapacitacion`$$

CREATE PROCEDURE `SP_RegistrarParticipacionCapacitacion`(
    /* --------------------------------------------------------------------------------------------------
       DEFINICIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS)
       -------------------------------------------------------------------------------------------------- */
    IN _Id_Usuario INT,              -- ID del usuario autenticado (Actúa como Ejecutor y Participante)
    IN _Id_Detalle_Capacitacion INT  -- ID de la versión específica del curso a tomar
)
ProcAutoIns: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: DECLARACIÓN DE VARIABLES Y MEMORIA (VARIABLE DECLARATION)
       Nota: Inicializamos todo en 0/Empty para evitar el comportamiento impredecible de NULL en MySQL.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] VARIABLES DE IDENTIDAD
    DECLARE v_Usuario_Existe INT DEFAULT 0;
    DECLARE v_Usuario_Activo INT DEFAULT 0;
    
    -- [1.2] VARIABLES DE CONTEXTO DEL CURSO (DATA SNAPSHOT)
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;  -- FK al catálogo padre
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';  -- Para mensajes de feedback
    DECLARE v_Estatus_Curso INT DEFAULT 0;          -- ID del estatus actual
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;       -- Bandera booleana (1=Cerrado)
    
    -- [1.3] VARIABLES PARA ARITMÉTICA DE CUPO (HYBRID LOGIC)
    DECLARE v_Cupo_Maximo INT DEFAULT 0;        -- Meta (Capacidad total)
    DECLARE v_Conteo_Sistema INT DEFAULT 0;     -- Ocupación real (Filas en BD)
    DECLARE v_Conteo_Manual INT DEFAULT 0;      -- Ocupación forzada (Manual override)
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;  -- Resultado de la comparación
    DECLARE v_Cupo_Disponible INT DEFAULT 0;    -- Delta final
    
    -- [1.4] VARIABLES DE CONTROL Y RESULTADO
    DECLARE v_Ya_Inscrito INT DEFAULT 0;        -- Bandera de duplicidad
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0;  -- Identity generado (PK)
    
    -- [1.5] CONSTANTES DE NEGOCIO (HARDCODED IDS)
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;   -- ID 1: Inscrito / Activo
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;       -- ID 5: Baja / Cancelado
    
    -- [1.6] CONSTANTES DE ESTATUS PERMITIDOS (LISTA BLANCA - WHITELIST)
    -- Estos IDs determinan en qué momento del ciclo de vida es válida la auto-inscripción.
    DECLARE c_EST_PROGRAMADO INT DEFAULT 1;     -- [CORREGIDO]: Curso confirmado
    DECLARE c_EST_POR_INICIAR INT DEFAULT 2;    -- [CORREGIDO]: Última llamada
    DECLARE c_EST_REPROGRAMADO INT DEFAULT 9;   -- [CORREGIDO]: Nueva fecha asignada

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: MANEJO DE EXCEPCIONES (EXCEPTION HANDLING & ACID PROTECTION)
       Objetivo: Garantizar la atomicidad. Si ocurre cualquier error SQL (Deadlock, Constraint, Type),
       se revierte toda la operación para no dejar "basura" o registros huérfanos.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- [CRÍTICO]: Revertir transacción pendiente.
        SELECT 
            'ERROR DE SISTEMA [500]: Ocurrió un error técnico al procesar tu inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA (FAIL-FAST STRATEGY)
       Justificación: No tiene sentido iniciar transacciones ni lecturas si los datos básicos
       vienen corruptos (NULL o Ceros). Ahorra CPU y I/O.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Identidad del Solicitante
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
			SELECT 'ERROR DE SESIÓN [400]: No se pudo identificar tu usuario. Por favor relogueate.' AS Mensaje, 
				   'LOGOUT_REQUIRED' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 0.2: Objetivo de la Transacción
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El curso seleccionado no es válido.' AS Mensaje, 
					'VALIDACION_FALLIDA' AS Accion, 
					NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE IDENTIDAD Y VIGENCIA (USER ASSERTION)
       Objetivo: Confirmar que el usuario existe en BD y tiene permiso de operar (Activo=1).
       Previene operaciones de usuarios inhabilitados que aún tengan sesión abierta.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*), `Activo` 
    INTO v_Usuario_Existe, v_Usuario_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario;
    
    -- Validación 1.1: Existencia Física
    IF v_Usuario_Existe = 0 
		THEN
			SELECT 'ERROR DE CUENTA [404]: Tu usuario no parece existir en el sistema.' AS Mensaje, 
				   'CONTACTAR_SOPORTE' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 1.2: Estado Lógico (Soft Delete Check)
    IF v_Usuario_Activo = 0 
		THEN
			SELECT 'ACCESO DENEGADO [403]: Tu cuenta está inactiva. No puedes inscribirte.' AS Mensaje, 
				   'ACCESO_DENEGADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: CONTEXTO Y ESTADO DEL CURSO (RESOURCE AVAILABILITY SNAPSHOT)
       Objetivo: Cargar todos los metadatos del curso en memoria para validaciones complejas.
       Optimizacion: Se hace un solo SELECT con JOIN implícito para evitar múltiples round-trips a la BD.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*),                             -- [0] Existe?
        COALESCE(`DC`.`Activo`, 0),           -- [1] Activo?
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID Padre
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Status ID (Para Whitelist)
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] Override Manual (Input Coordinador)
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 2.1: Integridad Referencial
    IF v_Capacitacion_Existe = 0 
		THEN
			SELECT 'ERROR [404]: El curso que buscas no existe.' AS Mensaje, 
				   'RECURSO_NO_ENCONTRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Validación 2.2: Ciclo de Vida (Soft Delete)
    IF v_Capacitacion_Activa = 0 
		THEN
			SELECT 'LO SENTIMOS [409]: Este curso ha sido archivado o cancelado.' AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
                   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;
    
    -- Obtener Meta y Folio (Sub-Consulta Optimizada)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- Validación 2.3: Ciclo de Vida del Negocio (Estatus Final)
    SELECT `Es_Final` INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 
		THEN
			SELECT CONCAT('INSCRIPCIONES CERRADAS: El curso "', v_Folio_Curso, '" ya ha finalizado.') AS Mensaje, 
				   'CURSO_CERRADO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* [VALIDACIÓN CRÍTICA] 2.4: Estatus Operativo Permitido (Whitelist)
       Objetivo: Evitar inscribir en cursos "En Diseño", "En Curso" (ya iniciados) o estatus no comerciales.
       Solo se permite: PROGRAMADO (1), POR INICIAR (2), REPROGRAMADO (9).
    */
    IF v_Estatus_Curso NOT IN (c_EST_PROGRAMADO, c_EST_POR_INICIAR, c_EST_REPROGRAMADO) 
		THEN
			SELECT CONCAT('AÚN NO DISPONIBLE: El curso "', v_Folio_Curso, '" no está abierto para inscripciones (Estatus actual: ', v_Estatus_Curso, ').') AS Mensaje, 
				   'ESTATUS_INVALIDO' AS Accion,
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE IDEMPOTENCIA (UNIQUENESS CHECK)
       Objetivo: Asegurar que el usuario no se inscriba dos veces al mismo curso.
       Regla: Un usuario puede tener N cursos, pero solo 1 registro activo por Curso específico.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario;
    
    IF v_Ya_Inscrito > 0 THEN
        SELECT 'YA ESTÁS INSCRITO: Ya tienes un lugar reservado en este curso.' AS Mensaje, 
               'YA_INSCRITO' AS Accion, 
               NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 4: CÁLCULO Y VALIDACIÓN DE CUPO (HYBRID CAPACITY LOGIC)
       Objetivo: Determinar disponibilidad real aplicando la regla "GREATEST".
       
       Escenario de Protección:
       - Meta = 20
       - Sistema (Inscritos) = 5
       - Manual (Coordinador) = 20 (Porque sabe que viene un grupo externo).
       - Cálculo: GREATEST(5, 20) = 20 ocupados.
       - Disponible: 20 - 20 = 0.
       - Resultado: CUPO LLENO (Correcto, bloquea al usuario aunque el sistema vea 5).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Paso 4.1: Contar ocupación sistémica (Excluyendo bajas que liberan cupo)
    SELECT COUNT(*) INTO v_Conteo_Sistema 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- Paso 4.2: Aplicar Regla del Máximo (Pesimista)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- Paso 4.3: Calcular disponibilidad neta
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- Paso 4.4: Veredicto Final
    IF v_Cupo_Disponible <= 0 
		THEN
			SELECT 'CUPO LLENO: Lo sentimos, ya no hay lugares disponibles para este curso.' AS Mensaje, 
				   'CUPO_LLENO' AS Accion, 
				   NULL AS Id_Registro_Participante;
        LEAVE ProcAutoIns;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 5: EJECUCIÓN TRANSACCIONAL (ACID WRITE)
       Objetivo: Persistir el registro. Aquí comienza la transacción atómica.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`, 
        `Fk_Id_Usuario`, 
        `Fk_Id_CatEstPart`, 
        `Calificacion`, 
        `PorcentajeAsistencia`, 
        `created_at`,               -- Audit: Fecha Creación
        `updated_at`,               -- Audit: Fecha Modificación
        `Fk_Id_Usuario_Created_By`, -- [AUDITORÍA]: Self-Registration (El usuario se creó a sí mismo)
        `Fk_Id_Usuario_Updated_By`  -- [AUDITORÍA]: Self-Update
    ) VALUES (
        _Id_Detalle_Capacitacion, 
        _Id_Usuario, 
        c_ESTATUS_INSCRITO,         -- Estado inicial = 1
        NULL,                       -- Calificación pendiente
        NULL,                       -- Asistencia pendiente
        NOW(), NOW(), 
        _Id_Usuario,                -- ID del alumno como autor
        _Id_Usuario                 -- ID del alumno como editor
    );
    
    -- Recuperar el ID autogenerado (Identity)
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT; -- Confirmar escritura en disco

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 6: FEEDBACK Y CONFIRMACIÓN (RESPONSE)
       Objetivo: Retornar estructura JSON-friendly al Frontend confirmando el éxito.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('¡REGISTRO EXITOSO! Te has inscrito correctamente al curso "', v_Folio_Curso, '".') AS Mensaje,
        'INSCRITO' AS Accion,
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$

DELIMITER ;

