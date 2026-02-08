/* ====================================================================================================
   PROCEDIMIENTO ALMACENADO: SP_EditarModalidadCapacitacion
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO TÉCNICO Y DE NEGOCIO (BUSINESS CONTEXT)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional de alta fidelidad encargado de modificar los atributos fundamentales de 
   una "Modalidad de Capacitación" (`Cat_Modalidad_Capacitacion`) existente en el catálogo corporativo.

   [OBJETIVO ESTRATÉGICO]:
   Permitir al administrador corregir o actualizar la identidad (`Código`, `Nombre`) y el contexto 
   operativo (`Descripción`) de una modalidad.
   
   [IMPORTANCIA CRÍTICA]:
   Las modalidades (Presencial, Virtual, Híbrido) son la base de la logística de cursos. Un error de 
   integridad aquí (ej: duplicar conceptos o perder descripciones) corrompería la inteligencia de 
   negocios de todos los reportes históricos y futuros.

   Este SP garantiza la consistencia ACID (Atomicidad, Consistencia, Aislamiento, Durabilidad) en un 
   entorno multi-usuario de alta concurrencia.

   ----------------------------------------------------------------------------------------------------
   II. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] OBLIGATORIEDAD DE DATOS (DATA INTEGRITY):
      - Principio: "Todo o Nada". No se permite persistir una modalidad sin `Código` o sin `Nombre`.
      - Justificación: Un registro anónimo o sin clave técnica rompe la integridad visual de los 
        selectores (dropdowns) y las referencias en el backend.

   [RN-02] EXCLUSIÓN PROPIA (GLOBAL UNIQUENESS):
      - Regla A: El nuevo `Código` no puede pertenecer a OTRA modalidad (`Id <> _Id_Modalidad`).
      - Regla B: El nuevo `Nombre` no puede pertenecer a OTRA modalidad.
      - Nota: Es perfectamente legal que el registro coincida consigo mismo (Idempotencia).
      - Implementación: Esta validación se realiza "Bajo Llave" (dentro de la transacción con bloqueo).

   [RN-03] IDEMPOTENCIA (OPTIMIZACIÓN DE I/O):
      - Antes de escribir en disco, el SP compara el estado actual (`Snapshot`) contra los inputs.
      - Si son matemáticamente idénticos, retorna éxito ('SIN_CAMBIOS') inmediatamente.
      - Beneficio: Evita escrituras innecesarias en el Transaction Log, reduce el crecimiento de la 
        BD y mantiene intacta la fecha de auditoría `updated_at`.

   ----------------------------------------------------------------------------------------------------
   III. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   ----------------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LOS DEADLOCKS (ABRAZOS MORTALES)]:
   En un escenario de "Intercambio" (Swap Scenario), donde:
      - Usuario A quiere renombrar la Modalidad 1 como 'VIRTUAL'.
      - Usuario B quiere renombrar la Modalidad 2 como 'PRESENCIAL'.
   Si ambos registros ya existen y se cruzan las referencias, y si bloquean los recursos en orden inverso,
   el motor de base de datos detectará un ciclo y matará uno de los procesos.

   [LA SOLUCIÓN MATEMÁTICA - ALGORITMO DE ORDENAMIENTO]:
   Implementamos el patrón de "Bloqueo Determinístico Total":
   
   1. FASE DE RECONOCIMIENTO (Dirty Read):
      Identificamos todos los IDs potenciales involucrados:
        a) El ID que edito (Target).
        b) El ID que actualmente posee el Código que quiero usar (Conflicto A).
        c) El ID que actualmente posee el Nombre que quiero usar (Conflicto B).
   
   2. FASE DE ORDENAMIENTO:
      Ordenamos estos IDs numéricamente de MENOR a MAYOR.
   
   3. FASE DE EJECUCIÓN:
      Adquirimos los bloqueos (`FOR UPDATE`) siguiendo estrictamente ese orden "en fila india".
   
   Resultado: Todos los procesos compiten en la misma dirección. Cero Deadlocks garantizados.

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE SALIDA (OUTPUT SPECIFICATION)
   ----------------------------------------------------------------------------------------------------
   Retorna un resultset de una sola fila con:
      - [Mensaje]: Feedback descriptivo y humano para la UI.
      - [Accion]: Código de estado ('ACTUALIZADA', 'SIN_CAMBIOS', 'CONFLICTO').
      - [Id_Modalidad]: Identificador del recurso manipulado.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarModalidadCapacitacion`$$

CREATE PROCEDURE `SP_EditarModalidadCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el formulario web.
       Se asume que son cadenas de texto que requieren limpieza.
       ----------------------------------------------------------------- */
    IN _Id_Modalidad INT,           -- [OBLIGATORIO] PK del registro a editar (Target).
    IN _Codigo       VARCHAR(50),   -- [OBLIGATORIO] Nuevo Código (ej: 'VIRT-02').
    IN _Nombre       VARCHAR(255),  -- [OBLIGATORIO] Nuevo Nombre (ej: 'VIRTUAL ASINCRÓNICO').
    IN _Descripcion  VARCHAR(255)   -- [OPCIONAL] Nueva Descripción (Contexto).
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores en memoria para la lógica del procedimiento.
       ======================================================================================== */
    
    /* [Snapshots]: Almacenan la "foto" del registro ANTES de editarlo. 
       Son vitales para comparar si hubo cambios reales (Lógica de Idempotencia). */
    DECLARE v_Cod_Act  VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act  VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act VARCHAR(255) DEFAULT NULL;
    
    /* [IDs de Conflicto]: Identifican a "los otros" registros que podrían estorbar.
       Se llenan durante la Fase de Reconocimiento. */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ¿Quién tiene ya este Código?
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ¿Quién tiene ya este Nombre?
    
    /* [Variables de Algoritmo de Bloqueo]: Auxiliares para ordenar y ejecutar los locks.
       Nos permiten estructurar la "Fila India" de bloqueos. */
    DECLARE v_L1 INT DEFAULT NULL;   -- Candidato 1 a bloquear
    DECLARE v_L2 INT DEFAULT NULL;   -- Candidato 2 a bloquear
    DECLARE v_L3 INT DEFAULT NULL;   -- Candidato 3 a bloquear
    DECLARE v_Min INT DEFAULT NULL;  -- El menor ID de la ronda actual
    DECLARE v_Existe INT DEFAULT NULL; -- Validación booleana de éxito del lock

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062).
       Permite manejar la excepción sin abortar el flujo inmediatamente. */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* [Variables de Diagnóstico]: Para el análisis Post-Mortem en caso de fallo.
       Permiten decirle al usuario EXACTAMENTE qué campo causó el error. */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Capturar excepciones técnicas y convertirlas en respuestas controladas.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Si ocurre una "Race Condition" en el último milisegundo (alguien insertó el duplicado
       justo antes de nuestro UPDATE y después de nuestro SELECT), no abortamos.
       Acción: Encendemos la bandera v_Dup = 1 para activar la rutina de recuperación al final. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Ante fallos catastróficos (Disco lleno, Red caída, Error de Sintaxis).
       Acción: Abortamos todo (ROLLBACK) y propagamos el error original (RESIGNAL) para el log. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Limpiar la entrada y rechazar basura antes de gastar recursos de transacción.
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta más adelante. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLAS DE NEGOCIO)
       Validamos la integridad básica de la petición. */
    
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Modalidad inválido.';
    END IF;

    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       Propósito: Adquirir recursos en orden estricto (Menor a Mayor) para evitar ciclos de espera.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "escaneamos" el entorno para identificar a los actores involucrados sin bloquear.
       Esto nos permite construir la lista de IDs que necesitamos asegurar.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar al Objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* Check de Existencia: Si no existe, abortamos. (Pudo ser borrado por otro admin hace un segundo) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad que intenta editar no existe.';
    END IF;

    /* B) Identificar Conflicto de CÓDIGO 
       ¿Alguien más tiene el código que quiero usar? (Solo buscamos si el código cambió) */
    IF _Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    END IF;

    /* C) Identificar Conflicto de NOMBRE 
       ¿Alguien más tiene el nombre que quiero usar? (Solo buscamos si el nombre cambió) */
    IF _Nombre <> v_Nom_Act THEN
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS (EL ALGORITMO)
       Ordenamos los IDs detectados y los bloqueamos secuencialmente.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de candidatos a bloquear */
    SET v_L1 = _Id_Modalidad;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables 
       (Ej: Si el conflicto de código y nombre es el mismo registro, no intentamos bloquearlo dos veces) */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    /* Encontramos el mínimo valor no nulo entre L1, L2 y L3 */
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        /* Bloqueo Pesimista sobre el ID menor */
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
        
        /* Marcar como procesado (borrar del pool) para la siguiente ronda */
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 2: Bloquear el Siguiente ID (El del medio) --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 3: Bloquear el ID Mayor (Último) --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       Propósito: Aplicar validaciones definitivas con la certeza de que nadie más mueve los datos.
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Leemos el estado definitivo del registro.
       (Pudo haber cambiado en los milisegundos previos al bloqueo o durante la espera del lock). */
    SELECT `Codigo`, `Nombre`, `Descripcion`
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act
    FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Id_CatModalCap` = _Id_Modalidad; 

    /* Check Anti-Zombie: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Cod_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos Snapshot vs Inputs. 
       Usamos `<=>` (Null-Safe Equality) para manejar correctamente los NULLs en la Descripción. 
       Si todo es igual, no tiene sentido hacer un UPDATE. */
    IF (v_Cod_Act <=> _Codigo) 
       AND (v_Nom_Act = _Nombre) 
       AND (v_Desc_Act <=> _Descripcion) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Modalidad AS Id_Modalidad;
        LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos duplicados reales bajo lock. Esta validación es 100% fiable. */
    
    /* A) Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatModalCap` INTO v_Id_Error FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otra Modalidad.';
    END IF;

    /* B) Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatModalCap` INTO v_Id_Error FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otra Modalidad.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE FÍSICO)
       Propósito: Aplicar los cambios físicos en el disco.
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error antes de intentar escribir

    UPDATE `Cat_Modalidad_Capacitacion`
    SET `Codigo`      = _Codigo,
        `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `updated_at`  = NOW() -- Auditoría automática
    WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo de inserción fantasma justo antes del update.
       ======================================================================================== */
    
    /* Si v_Dup = 1, el UPDATE falló por una violación de UNIQUE KEY inesperada. */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem: ¿Qué campo causó el error? */
        SET v_Id_Conflicto = NULL;
        
        /* Prueba 1: ¿Fue Código? */
        SELECT `Id_CatModalCap` INTO v_Id_Conflicto FROM `Cat_Modalidad_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
             SET v_Campo_Error = 'CODIGO';
        ELSE
             /* Prueba 2: Fue Nombre */
             SELECT `Id_CatModalCap` INTO v_Id_Conflicto FROM `Cat_Modalidad_Capacitacion` 
             WHERE `Nombre` = _Nombre AND `Id_CatModalCap` <> _Id_Modalidad LIMIT 1;
             SET v_Campo_Error = 'NOMBRE';
        END IF;

        /* Devolvemos el error estructurado al Frontend */
        SELECT 'Error de Concurrencia: Conflicto detectado al guardar.' AS Mensaje, 
               'CONFLICTO' AS Accion, 
               v_Campo_Error AS Campo,
               v_Id_Conflicto AS Id_Conflicto;
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 7: CONFIRMACIÓN EXITOSA
       Si llegamos aquí, todo salió bien. Hacemos permanentes los cambios.
       ======================================================================================== */
    COMMIT;
    
    SELECT 'ÉXITO: Modalidad actualizada correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Modalidad AS Id_Modalidad;

END$$

DELIMITER ;