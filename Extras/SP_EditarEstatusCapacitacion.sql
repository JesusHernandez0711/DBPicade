/* ============================================================================================
   PROCEDIMIENTO: SP_EditarEstatusCapacitacion
   ============================================================================================
   
   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Es el motor transaccional blindado encargado de modificar los atributos descriptivos y la
   Lógica de Negocio (`Es_Final`) de un Estatus de Capacitación existente.

   [POR QUÉ ES CRÍTICO]:
   Este catálogo gobierna el comportamiento del sistema. 
   - Modificar un nombre es trivial.
   - Pero modificar la bandera `Es_Final` tiene consecuencias operativas masivas: puede liberar
     o bloquear la edición de miles de cursos e instructores asociados.
   
   Por ello, este SP no es un simple UPDATE. Es una orquestación de bloqueos y validaciones 
   diseñada para operar bajo fuego (alta concurrencia) sin corromper la data.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE CONCURRENCIA (DETERMINISTIC LOCKING PATTERN)
   --------------------------------------------------------------------------------------------
   [EL PROBLEMA DE LOS ABRAZOS MORTALES (DEADLOCKS)]:
   Imagina que el Admin A quiere renombrar el estatus 'X' a 'Y', y al mismo tiempo el Admin B
   quiere renombrar el estatus 'Y' a 'X'. 
   Si bloquean los registros en orden diferente, la base de datos mata uno de los procesos.

   [LA SOLUCIÓN MATEMÁTICA]:
   Implementamos el patrón de "Bloqueo Determinístico":
   1. Identificamos todos los IDs involucrados (El que edito + El que tiene el código que quiero + El que tiene el nombre que quiero).
   2. Los ordenamos de MENOR a MAYOR.
   3. Los bloqueamos (`FOR UPDATE`) siguiendo estrictamente ese orden "en fila india".
   Resultado: Cero Deadlocks garantizados.

   --------------------------------------------------------------------------------------------
   III. REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   --------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD TOTAL: Código, Nombre y Es_Final son obligatorios.
   [RN-02] EXCLUSIÓN PROPIA: Puedo llamarme igual a mí mismo, pero no igual a mi vecino.
   [RN-03] IDEMPOTENCIA: Si guardas sin cambios, el sistema lo detecta y no toca el disco duro.

   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EditarEstatusCapacitacion`$$

CREATE PROCEDURE `SP_EditarEstatusCapacitacion`(
    /* -----------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el formulario web.
       ----------------------------------------------------------------- */
    IN _Id_Estatus  INT,           -- [OBLIGATORIO] PK del registro a editar (Target).
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Nuevo Código (o el mismo).
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nuevo Nombre (o el mismo).
    IN _Descripcion VARCHAR(255),  -- [OPCIONAL] Nueva Descripción (Contexto).
    IN _Es_Final    TINYINT(1)     -- [CRÍTICO] 0=Bloqueante (Vivo), 1=Liberador (Finalizado).
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTEXTO
       Propósito: Inicializar los contenedores en memoria para la lógica del procedimiento.
       ======================================================================================== */
    
    /* [Snapshots]: Almacenan la "foto" del registro ANTES de editarlo. 
       Vitales para comparar si hubo cambios reales (Idempotencia). */
    DECLARE v_Cod_Act    VARCHAR(50)  DEFAULT NULL;
    DECLARE v_Nom_Act    VARCHAR(255) DEFAULT NULL;
    DECLARE v_Desc_Act   VARCHAR(255) DEFAULT NULL;
    DECLARE v_Final_Act  TINYINT(1)   DEFAULT NULL;
    
    /* [IDs de Conflicto]: Identifican a "los otros" registros que podrían estorbar. */
    DECLARE v_Id_Conflicto_Cod INT DEFAULT NULL; -- ¿Quién tiene ya este Código?
    DECLARE v_Id_Conflicto_Nom INT DEFAULT NULL; -- ¿Quién tiene ya este Nombre?

    /* [Variables de Algoritmo de Bloqueo]: Auxiliares para ordenar y ejecutar los locks. */
    DECLARE v_L1 INT DEFAULT NULL;   -- Candidato 1 a bloquear
    DECLARE v_L2 INT DEFAULT NULL;   -- Candidato 2 a bloquear
    DECLARE v_L3 INT DEFAULT NULL;   -- Candidato 3 a bloquear
    DECLARE v_Min INT DEFAULT NULL;  -- El menor de la ronda actual
    DECLARE v_Existe INT DEFAULT NULL; -- Validación de éxito del lock

    /* [Bandera de Control]: Semáforo para detectar errores de concurrencia (Error 1062). */
    DECLARE v_Dup TINYINT(1) DEFAULT 0;

    /* [Variables de Diagnóstico]: Para el análisis Post-Mortem en caso de fallo. */
    DECLARE v_Campo_Error VARCHAR(20) DEFAULT NULL;
    DECLARE v_Id_Error    INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (SISTEMA DE DEFENSA)
       Propósito: Capturar excepciones técnicas y convertirlas en respuestas controladas.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062)
       Objetivo: Si ocurre una "Race Condition" en el último milisegundo (alguien insertó el duplicado
       justo antes de nuestro UPDATE), no abortamos. Activamos la bandera v_Dup. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Ante fallos catastróficos (Disco lleno, Red caída), abortamos todo (ROLLBACK). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Limpiar la entrada y rechazar basura antes de gastar recursos de transacción.
       ======================================================================================== */
    
    /* 2.1 LIMPIEZA (TRIM & NULLIF)
       Quitamos espacios y convertimos cadenas vacías a NULL para validar. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');
    /* Sanitización de Lógica: Si Es_Final viene NULL, asumimos FALSE (0) por seguridad */
    SET _Es_Final    = IFNULL(_Es_Final, 0);

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (REGLAS DE NEGOCIO) */
    
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Identificador de Estatus inválido.';
    END IF;

    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.';
    END IF;

    /* Validación de Dominio: Es_Final es binario */
    IF _Es_Final NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El campo Es_Final solo acepta 0 o 1.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: ESTRATEGIA DE BLOQUEO DETERMINÍSTICO (PREVENCIÓN DE DEADLOCKS)
       Propósito: Adquirir recursos en orden estricto (Menor a Mayor) para evitar ciclos de espera.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RECONOCIMIENTO (LECTURA SUCIA / NO BLOQUEANTE)
       Primero "escaneamos" el entorno para identificar a los actores involucrados sin bloquear.
       ---------------------------------------------------------------------------------------- */
    
    /* A) Identificar al Objetivo (Target) */
    SELECT `Codigo`, `Nombre` INTO v_Cod_Act, v_Nom_Act
    FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus;

    /* Si no existe, abortamos. (Pudo ser borrado por otro admin hace un segundo) */
    IF v_Cod_Act IS NULL AND v_Nom_Act IS NULL THEN 
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus que intenta editar no existe.';
    END IF;

    /* B) Identificar Conflicto de CÓDIGO (¿Alguien más tiene el código que quiero?) */
    IF _Codigo <> IFNULL(v_Cod_Act, '') THEN
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto_Cod 
        FROM `Cat_Estatus_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    END IF;

    /* C) Identificar Conflicto de NOMBRE (¿Alguien más tiene el nombre que quiero?) */
    IF _Nombre <> v_Nom_Act THEN
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto_Nom 
        FROM `Cat_Estatus_Capacitacion` 
        WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: EJECUCIÓN DE BLOQUEOS ORDENADOS
       Ordenamos los IDs detectados y los bloqueamos secuencialmente.
       ---------------------------------------------------------------------------------------- */
    
    /* Llenamos el pool de candidatos */
    SET v_L1 = _Id_Estatus;
    SET v_L2 = v_Id_Conflicto_Cod;
    SET v_L3 = v_Id_Conflicto_Nom;

    /* Normalización: Eliminar duplicados en las variables */
    IF v_L2 = v_L1 THEN SET v_L2 = NULL; END IF;
    IF v_L3 = v_L1 THEN SET v_L3 = NULL; END IF;
    IF v_L3 = v_L2 THEN SET v_L3 = NULL; END IF;

    /* --- RONDA 1: Bloquear el ID Menor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
        /* Marcar como procesado */
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 2: Bloquear el Siguiente ID --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
        IF v_L1 = v_Min THEN SET v_L1 = NULL; END IF;
        IF v_L2 = v_Min THEN SET v_L2 = NULL; END IF;
        IF v_L3 = v_Min THEN SET v_L3 = NULL; END IF;
    END IF;

    /* --- RONDA 3: Bloquear el ID Mayor --- */
    SET v_Min = NULL;
    IF v_L1 IS NOT NULL THEN SET v_Min = v_L1; END IF;
    IF v_L2 IS NOT NULL AND (v_Min IS NULL OR v_L2 < v_Min) THEN SET v_Min = v_L2; END IF;
    IF v_L3 IS NOT NULL AND (v_Min IS NULL OR v_L3 < v_Min) THEN SET v_Min = v_L3; END IF;

    IF v_Min IS NOT NULL THEN
        SELECT 1 INTO v_Existe FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = v_Min FOR UPDATE;
    END IF;

    /* ========================================================================================
       BLOQUE 4: LÓGICA DE NEGOCIO (BAJO PROTECCIÓN DE LOCKS)
       Propósito: Aplicar validaciones definitivas con la certeza de que nadie más mueve los datos.
       ======================================================================================== */

    /* 4.1 RE-LECTURA AUTORIZADA
       Leemos el estado definitivo. (Pudo haber cambiado en los milisegundos previos al bloqueo). */
    SELECT `Codigo`, `Nombre`, `Descripcion`, `Es_Final`
    INTO v_Cod_Act, v_Nom_Act, v_Desc_Act, v_Final_Act
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Id_CatEstCap` = _Id_Estatus; 

    /* Check Anti-Zombie: Si al bloquear descubrimos que el registro fue borrado */
    IF v_Cod_Act IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [410]: El registro desapareció durante la transacción.';
    END IF;

    /* 4.2 DETECCIÓN DE IDEMPOTENCIA (SIN CAMBIOS)
       Comparamos Snapshot vs Inputs. Usamos `<=>` (Null-Safe) para manejar NULLs en Descripción. */
    IF (v_Cod_Act <=> _Codigo) 
       AND (v_Nom_Act = _Nombre) 
       AND (v_Desc_Act <=> _Descripcion)
       AND (v_Final_Act = _Es_Final) THEN
        
        COMMIT; -- Liberamos locks inmediatamente
        
        /* Retorno anticipado para ahorrar I/O */
        SELECT 'AVISO: No se detectaron cambios en la información.' AS Mensaje, 'SIN_CAMBIOS' AS Accion, _Id_Estatus AS Id_Estatus;
        LEAVE THIS_PROC;
    END IF;

    /* 4.3 VALIDACIÓN FINAL DE UNICIDAD (PRE-UPDATE CHECK)
       Verificamos duplicados reales bajo lock. */
    
    /* Validación por CÓDIGO */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstCap` INTO v_Id_Error FROM `Cat_Estatus_Capacitacion` 
    WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Estatus.';
    END IF;

    /* Validación por NOMBRE */
    SET v_Id_Error = NULL;
    SELECT `Id_CatEstCap` INTO v_Id_Error FROM `Cat_Estatus_Capacitacion` 
    WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
    
    IF v_Id_Error IS NOT NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya pertenece a otro Estatus.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: PERSISTENCIA (UPDATE)
       Propósito: Aplicar los cambios físicos.
       ======================================================================================== */
    
    SET v_Dup = 0; -- Resetear bandera de error

    UPDATE `Cat_Estatus_Capacitacion`
    SET `Codigo`      = _Codigo,
        `Nombre`      = _Nombre,
        `Descripcion` = _Descripcion,
        `Es_Final`    = _Es_Final,
        `updated_at`  = NOW() -- Actualizamos la auditoría temporal.
    WHERE `Id_CatEstCap` = _Id_Estatus;

    /* ========================================================================================
       BLOQUE 6: MANEJO DE COLISIÓN TARDÍA (RECUPERACIÓN DE ERROR 1062)
       Propósito: Gestionar el caso extremo de inserción fantasma justo antes del update.
       ======================================================================================== */
    IF v_Dup = 1 THEN
        ROLLBACK;
        
        /* Diagnóstico Post-Mortem */
        SET v_Id_Conflicto = NULL;
        
        /* ¿Fue Código? */
        SELECT `Id_CatEstCap` INTO v_Id_Conflicto FROM `Cat_Estatus_Capacitacion` 
        WHERE `Codigo` = _Codigo AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;

        IF v_Id_Conflicto IS NOT NULL THEN
             SET v_Campo_Error = 'CODIGO';
        ELSE
             /* Fue Nombre */
             SELECT `Id_CatEstCap` INTO v_Id_Conflicto FROM `Cat_Estatus_Capacitacion` 
             WHERE `Nombre` = _Nombre AND `Id_CatEstCap` <> _Id_Estatus LIMIT 1;
             SET v_Campo_Error = 'NOMBRE';
        END IF;

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
    
    SELECT 'ÉXITO: Estatus actualizado correctamente.' AS Mensaje, 
           'ACTUALIZADA' AS Accion, 
           _Id_Estatus AS Id_Estatus;

END$$

DELIMITER ;