/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusUsuario
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO ESTRATÉGICO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure actúa como el **Motor de Gobierno de Identidades** (Identity Governance Engine) 
   del sistema. No es un simple "switch" de apagado/encendido; es un orquestador de ciclo de vida que 
   garantiza la continuidad operativa de la empresa.

   [EL PROBLEMA DE NEGOCIO QUE RESUELVE]:
   En una organización de capacitación de alto rendimiento (como PEMEX), el capital humano es el activo 
   más crítico. La desactivación de un usuario no es un evento aislado, es un riesgo sistémico.
   
   * Escenario de Riesgo 1 (El Instructor Fantasma): Si un administrador desactiva por error a un 
     instructor que tiene un curso programado para mañana a las 8:00 AM, el sistema impide el acceso, 
     el instructor no llega, y se genera una pérdida financiera y de reputación ("Evento Acéfalo").
   
   * Escenario de Riesgo 2 (El Alumno Zombie): Si se da de baja a un alumno a mitad de un curso, 
     se corrompen las métricas de asistencia, las actas de calificación y los historiales de 
     cumplimiento normativo (SSPA).

   [SOLUCIÓN ARQUITECTÓNICA]:
   Se implementa un mecanismo de **"Baja Lógica Condicional"** (Conditional Soft Delete).
   Antes de permitir la desactivación, el sistema ejecuta un análisis forense en tiempo real de las 
   dependencias del usuario. Si el usuario es un "Nodo Activo" en la red de capacitación (Instructor 
   o Participante), la operación se bloquea automáticamente.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   
   [RN-01] PROTOCOLO ANTI-LOCKOUT (SEGURIDAD DE ACCESO):
      - Principio: "Seguridad contra el error humano propio".
      - Regla: Un usuario con privilegios de Administrador tiene estrictamente PROHIBIDO desactivar 
        su propia cuenta. Esto evita el escenario de "cerrar la puerta con las llaves adentro".

   [RN-02] INTEGRIDAD REFERENCIAL SINCRONIZADA (ATOMIC DATA CONSISTENCY):
      - Principio: "Una identidad, un estado".
      - Regla: El sistema PICADE maneja la identidad en dos capas:
           1. Capa de Acceso (`Usuarios`): Login y Credenciales.
           2. Capa Operativa (`Info_Personal`): Recursos Humanos y Catálogos.
      - Mecanismo: El SP garantiza atomicidad. Si se desactiva el Usuario, se fuerza la desactivación 
        inmediata de la ficha de Personal asociada. Esto limpia los selectores de "Instructores Disponibles" 
        en el frontend instantáneamente.

   [RN-03] CANDADO OPERATIVO DINÁMICO (THE DYNAMIC KILLSWITCH):
      - Principio: "Prioridad a la Operación Viva".
      - Definición: La baja de un usuario está subordinada a que no tenga compromisos activos.
      
      A) VECTOR DE INSTRUCTOR/FACILITADOR (`DatosCapacitaciones`):
         - Alcance: Aplica a cualquier usuario (Admin, Coordinador, Instructor) asignado como responsable 
           de un grupo.
         - Lógica de Bloqueo (Data-Driven):
             * Se consulta el estatus de la capacitación (`Cat_Estatus_Capacitacion`).
             * Se lee la bandera de control `Es_Final`.
             * Si `Es_Final = 0` (Falso): El curso está VIVO (Programado, En Curso, Por Iniciar, En Evaluación).
               -> ACCIÓN: BLOQUEO TOTAL (Error 409).
             * Si `Es_Final = 1` (Verdadero): El curso está MUERTO (Finalizado, Cancelado, Archivado).
               -> ACCIÓN: PERMITIR BAJA.

      B) VECTOR DE PARTICIPANTE (`Capacitaciones_Participantes`):
         - Alcance: Usuarios inscritos como alumnos.
         - Lógica de Bloqueo:
             * Se verifica si el usuario tiene estatus de inscripción 'Activo' (1) o 'Cursando' (2).
             * Y ADEMÁS, se verifica que el curso en sí mismo siga vivo (`Es_Final = 0`).
             * Si el curso fue cancelado, el alumno se libera automáticamente.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA Y RENDIMIENTO (PERFORMANCE SPECS)
   ----------------------------------------------------------------------------------------------------
   - ESTRATEGIA DE CONCURRENCIA: Implementación de **Bloqueo Pesimista** (`SELECT ... FOR UPDATE`).
     Esto "congela" la fila del usuario objetivo durante la transacción, asegurando que nadie más 
     pueda editar sus datos o cambiar su estatus en el milisegundo exacto en que validamos.
   - IDEMPOTENCIA: El sistema es inteligente. Si se solicita desactivar a un usuario que YA está 
     desactivado, el SP detecta la redundancia y retorna un mensaje de éxito ("SIN CAMBIOS") sin 
     realizar escrituras innecesarias en el disco duro, optimizando I/O.
   - TRAZABILIDAD: Se inyecta el ID del Administrador Ejecutor (`_Id_Admin_Ejecutor`) en los campos 
     de auditoría (`Updated_By`) para mantener un rastro forense de quién autorizó la baja.

   ----------------------------------------------------------------------------------------------------
   IV. MAPA DE RETORNO (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------
   Retorna un Resultset de una sola fila con la siguiente estructura:
      - [Mensaje] (VARCHAR): Descripción humana del resultado (ej: "ÉXITO: Usuario REACTIVADO").
      - [Id_Usuario] (INT): La llave primaria del usuario afectado.
      - [Accion] (VARCHAR): Token técnico para el frontend ('ACTIVADO', 'DESACTIVADO', 'SIN_CAMBIOS').
   ==================================================================================================== */


DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusUsuario`$$

CREATE PROCEDURE `SP_CambiarEstatusUsuario`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Admin_Ejecutor    INT,        -- [AUDITOR] ID del usuario que ejecuta la orden (Required).
    IN _Id_Usuario_Objetivo  INT,        -- [TARGET] ID del usuario que sufrirá el cambio (Required).
    IN _Nuevo_Estatus        TINYINT     -- [FLAG] Estado deseado: 1 = Activar (Alta), 0 = Desactivar (Baja).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ENTORNO
       Definición de contenedores para almacenar el estado de la base de datos y diagnósticos.
       ============================================================================================ */
    
    /* Punteros de Relación (Foreign Keys y Datos Maestros) */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; -- Para localizar la ficha de RH asociada.
    DECLARE v_Ficha_Objetivo  VARCHAR(50);      -- Para mostrar en el mensaje de éxito/error.
    
    /* Snapshot de Estado (Lectura actual de la BD) */
    DECLARE v_Estatus_Actual  TINYINT(1);       -- Estado actual en disco (0 o 1).
    DECLARE v_Existe          INT;              -- Bandera de existencia del registro.
    
    /* Variables de Diagnóstico para el Candado Operativo (Error Reporting) */
    DECLARE v_Curso_Conflictivo VARCHAR(50) DEFAULT NULL;  -- Número de capacitación que causa el bloqueo.
    DECLARE v_Estatus_Conflicto VARCHAR(255) DEFAULT NULL; -- Nombre del estatus del curso (ej: "EN CURSO").
    DECLARE v_Rol_Conflicto     VARCHAR(50) DEFAULT NULL;  -- Rol que juega el usuario en el conflicto.

    /* ============================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (DEFENSIVE CODING)
       ============================================================================================ */
    
    /* Handler Genérico de SQL:
       Ante cualquier error inesperado (caída de red, corrupción de datos, deadlock), 
       este bloque asegura que la transacción se revierta (ROLLBACK) para no dejar datos corruptos. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propaga el error original al backend para el log de errores.
    END;

    /* ============================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Verificaciones ligeras en memoria para rechazar peticiones inválidas antes de leer disco.
       ============================================================================================ */
    
    /* 2.1 Validación de Integridad de Parámetros */
    IF _Id_Admin_Ejecutor IS NULL OR _Id_Usuario_Objetivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Los IDs de ejecutor y objetivo son obligatorios.';
    END IF;

    /* 2.2 Validación de Dominio (Valores permitidos) */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE DATOS [400]: El estatus solo puede ser 1 (Activo) o 0 (Inactivo).';
    END IF;

    /* 2.3 Regla de Seguridad Anti-Lockout
       Impide que un administrador se suicide digitalmente. */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: Protocolo de Seguridad activado. No puedes desactivar tu propia cuenta de usuario.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: CANDADO OPERATIVO (INTEGRACIÓN DINÁMICA CON MÓDULO DE CAPACITACIÓN)
       Propósito: Validar que el usuario no sea una pieza clave en operaciones que están ocurriendo AHORA.
       Condición Crítica: Este bloque SOLO se ejecuta si la intención es APAGAR (0) al usuario.
       ============================================================================================ */
    IF _Nuevo_Estatus = 0 THEN
        
        /* ----------------------------------------------------------------------------------------
           3.1 VERIFICACIÓN DE ROL: FACILITADOR / INSTRUCTOR
           Objetivo: Detectar si el usuario es el responsable de impartir un curso activo.
           
           [LÓGICA DINÁMICA]:
           En lugar de listar IDs fijos (1,2,3...), consultamos la inteligencia del catálogo 
           `Cat_Estatus_Capacitacion` a través de la columna `Es_Final`.
           ---------------------------------------------------------------------------------------- */
        SELECT 
            C.Numero_Capacitacion, -- Para decirle al usuario EXACTAMENTE qué curso estorba
            EC.Nombre,             -- Para decirle en qué estado está ese curso
            'FACILITADOR/INSTRUCTOR' -- Etiqueta para el log de error
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `DatosCapacitaciones` DC
        /* JOIN 1: Llegar a la cabecera de la capacitación */
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        /* JOIN 2: Llegar a la configuración del estatus */
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        WHERE 
            /* Filtro 1: El usuario objetivo es el instructor asignado */
            DC.Fk_Id_Instructor = _Id_Usuario_Objetivo
            /* Filtro 2: El registro de detalle es el vigente (historial activo) */
            AND DC.Activo = 1 
            /* Filtro 3: La capacitación cabecera no ha sido borrada */
            AND C.Activo = 1
            
            /* [KILLSWITCH MAESTRO - DINÁMICO] 
               Si Es_Final = 0, el curso está VIVO (Programado, En Curso, Reprogramado, etc).
               Esto significa que NO podemos dejar el curso sin instructor. Bloqueo activado. */
            AND EC.Es_Final = 0 
        LIMIT 1; -- Con encontrar UNO solo basta para detener todo.

        /* Si se encontró un conflicto, abortamos la operación inmediatamente */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar al usuario. Actualmente funge como FACILITADOR en el curso ACTIVO con Folio "', v_Curso_Conflictivo, '" (Estatus Actual: ', v_Estatus_Conflicto, '). Este estatus se considera operativo (No Final). Para proceder, debe reasignar el curso a otro instructor o finalizar la capacitación.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

        /* ----------------------------------------------------------------------------------------
           3.2 VERIFICACIÓN DE ROL: PARTICIPANTE
           Objetivo: Detectar si el usuario es un alumno inscrito en un curso activo.
           
           [REGLA DE NEGOCIO]: Se mantiene la lógica para alumnos. No podemos borrar a alguien 
           que debe aparecer en la lista de asistencia de mañana.
           ---------------------------------------------------------------------------------------- */
        SELECT 
            C.Numero_Capacitacion,
            EP.Nombre,
            'PARTICIPANTE' -- Etiqueta informativa
        INTO 
            v_Curso_Conflictivo,
            v_Estatus_Conflicto,
            v_Rol_Conflicto
        FROM `Capacitaciones_Participantes` CP
        /* Cadena de Joins para llegar al Estatus del Curso */
        INNER JOIN `DatosCapacitaciones` DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        INNER JOIN `Cat_Estatus_Participante` EP ON CP.Fk_Id_CatEstPart = EP.Id_CatEstPart
        INNER JOIN `Cat_Estatus_Capacitacion` EC_Curso ON DC.Fk_Id_CatEstCap = EC_Curso.Id_CatEstCap
        WHERE 
            /* Filtro 1: El usuario es el participante */
            CP.Fk_Id_Usuario = _Id_Usuario_Objetivo
            /* Filtro 2: Su estatus de alumno es Inscrito (1) o Cursando (2) */
            AND CP.Fk_Id_CatEstPart IN (1, 2) 
            /* Filtro 3: El curso sigue existiendo */
            AND DC.Activo = 1
            /* [KILLSWITCH DINÁMICO] Validamos que el CURSO también esté vivo. 
               Si el curso ya terminó (Es_Final=1), el alumno ya es historia y se puede borrar. */
            AND EC_Curso.Es_Final = 0
        LIMIT 1;

        /* Si se encontró conflicto como alumno, abortamos */
        IF v_Curso_Conflictivo IS NOT NULL THEN
            SET @MensajeError = CONCAT('CONFLICTO OPERATIVO [409]: No se puede desactivar al usuario. Actualmente es PARTICIPANTE activo en el curso con Folio "', v_Curso_Conflictivo, '" (Estatus Alumno: ', v_Estatus_Conflicto, '). Debe darlo de baja del curso o esperar a que el curso finalice.');
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @MensajeError;
        END IF;

    END IF;

    /* ============================================================================================
       BLOQUE 4: FASE TRANSACCIONAL - AISLAMIENTO Y ESCRITURA
       Si llegamos aquí, el usuario superó todas las validaciones de negocio. Es seguro proceder.
       ============================================================================================ */
    START TRANSACTION;

    /* 4.1 ADQUISICIÓN DE SNAPSHOT Y BLOQUEO DE FILA (PESSIMISTIC LOCK)
       Seleccionamos los datos actuales del usuario y aplicamos `FOR UPDATE`.
       Esto impide que otra transacción modifique a este usuario mientras terminamos el proceso. */
    SELECT 1, `Fk_Id_InfoPersonal`, `Ficha`, `Activo`
    INTO v_Existe, v_Id_InfoPersonal, v_Ficha_Objetivo, v_Estatus_Actual
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* 4.2 Validación de Existencia (Integridad Referencial) */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El usuario solicitado no existe en la base de datos.';
    END IF;

    /* 4.3 Verificación de Idempotencia (Optimización)
       Si el usuario ya tiene el estatus que queremos ponerle, no hacemos nada.
       Esto ahorra escritura en logs de transacción y triggers. */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        COMMIT;
        SELECT CONCAT('SIN CAMBIOS: El usuario ya se encontraba en estado ', IF(_Nuevo_Estatus=1, 'ACTIVO', 'INACTIVO'), '.') AS Mensaje,
               _Id_Usuario_Objetivo AS Id_Usuario, 'SIN_CAMBIOS' AS Accion;
        LEAVE THIS_PROC;
    END IF;

    /* ============================================================================================
       BLOQUE 5: PERSISTENCIA SINCRONIZADA (CASCADE UPDATE LOGIC)
       Propósito: Aplicar el cambio de estado en todas las capas de identidad.
       ============================================================================================ */
    
    /* 5.1 Desactivar/Activar Acceso (Tabla Usuarios)
       Esto controla el Login y el acceso al sistema. */
    UPDATE `Usuarios`
    SET `Activo` = _Nuevo_Estatus,
        `Fk_Usuario_Updated_By` = _Id_Admin_Ejecutor, -- Auditoría: Quién lo hizo
        `updated_at` = NOW()                          -- Auditoría: Cuándo lo hizo
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* 5.2 Desactivar/Activar Operatividad (Tabla Info_Personal)
       Esto controla la aparición en catálogos de RH y listas de selección.
       Se ejecuta solo si existe una ficha de personal vinculada (Integridad de Datos). */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        UPDATE `Info_Personal`
        SET `Activo` = _Nuevo_Estatus,
            `Fk_Id_Usuario_Updated_By` = _Id_Admin_Ejecutor,
            `updated_at` = NOW()
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ============================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA (COMMIT & FEEDBACK)
       ============================================================================================ */
    COMMIT; -- Confirmar los cambios de forma permanente.

    /* Retorno de información al Frontend para notificaciones UI (Toasts) */
    SELECT 
        CONCAT('ÉXITO: El Usuario con Ficha "', v_Ficha_Objetivo, '" ha sido ', IF(_Nuevo_Estatus=1, 'REACTIVADO', 'DESACTIVADO'), ' correctamente.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Usuario,
        IF(_Nuevo_Estatus=1, 'ACTIVADO', 'DESACTIVADO') AS Accion;

END$$

DELIMITER ;