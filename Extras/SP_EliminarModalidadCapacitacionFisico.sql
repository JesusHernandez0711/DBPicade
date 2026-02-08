/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarModalidadCapacitacionFisico
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. FILOSOFÍA DE DISEÑO Y CONTEXTO ESTRATÉGICO (DATA GOVERNANCE)
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]:
   Este procedimiento representa el nivel máximo de autoridad administrativa en el ciclo de vida de los 
   datos: la "Eliminación Dura" (Hard Delete). Su ejecución implica la destrucción física de los 
   registros en las páginas de datos del disco duro para la tabla `Cat_Modalidad_Capacitacion`.

   [JUSTIFICACIÓN DE LA RIGIDEZ]:
   En un sistema de grado industrial, la información no es solo "texto", es una cadena de custodia. 
   Eliminar una modalidad que alguna vez fue utilizada es equivalente a borrar un eslabón en una cadena 
   de auditoría. Si borramos la modalidad "PRESENCIAL" y existen cursos históricos ligados a ella, 
   estamos creando "Datos Fantasma" o registros huérfanos que harían que los reportes de BI 
   (Business Intelligence) y las auditorías de cumplimiento (SSPA/PEMEX) fallen por inconsistencia.

   [DIFERENCIACIÓN DE PROCESOS]:
   1. BAJA LÓGICA (SP_CambiarEstatus...): Es la operación estándar. El dato se oculta pero se preserva 
      la integridad histórica. "El registro existió, pero ya no está disponible".
   2. BAJA FÍSICA (Este Procedimiento): Es una operación quirúrgica de limpieza. Su único fin es 
      eliminar errores de captura que JAMÁS llegaron a tener vida operativa (ej. creaste un registro 
      por error y lo borras 1 minuto después).

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE RIESGOS Y REGLAS DE BLINDAJE (INTEGRITY ARCHITECTURE)
   ----------------------------------------------------------------------------------------------------
   [RN-01] CANDADO HISTÓRICO ABSOLUTO (THE FORENSIC GUARD):
      - Principio: "Inmutabilidad del Rastro Operativo".
      - Regla de Negocio: Queda terminantemente PROHIBIDO el borrado físico si el registro aparece como 
        Foreign Key (FK) en la tabla de hechos `DatosCapacitaciones`.
      - Alcance Forense: El escaneo es agnóstico al estatus. No importa si el curso hijo está 
        'Activo', 'Cancelado', 'Finalizado' o 'Eliminado Lógicamente'. Si el ID de la modalidad 
        está en la tabla de hechos, el padre no puede ser destruido físicamente.

   [RN-02] ATOMICIDAD TRANSACCIONAL Y SERIALIZACIÓN (ACID):
      - Mecanismo: Implementación de Bloqueo Pesimista (`FOR UPDATE`).
      - Objetivo: Evitar la "Carrera de Destrucción". Esto impide que un Usuario A valide que no hay 
        hijos mientras un Usuario B crea un hijo nuevo en el microsegundo exacto antes del DELETE.
      - Nivel de Aislamiento: Se fuerza un comportamiento SERIALIZABLE para este recurso específico.

   [RN-03] DEFENSA EN PROFUNDIDAD (LAYERED DEFENSE):
      - Capa 1 (Aplicación): El SP valida el ID y la existencia del registro.
      - Capa 2 (Negocio): El SP escanea manualmente las tablas dependientes (`COUNT`).
      - Capa 3 (Motor): El Handler de MySQL para el error 1451 atrapa cualquier dependencia oculta 
        definida a nivel de esquema (Constraints).

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA DE ALTO NIVEL
   ----------------------------------------------------------------------------------------------------
   - TIPO: Destructivo / Atómico.
   - INPUT: _Id_Modalidad (INT).
   - OUTPUT: Resultset detallado con { Mensaje, Accion, Id_Eliminado }.
   - IMPACTO EN RENDIMIENTO: Al realizar un scan sobre `DatosCapacitaciones`, se recomienda que la 
     columna `Fk_Id_CatModalCap` en dicha tabla tenga un ÍNDICE activo para garantizar velocidad O(log n).

   ----------------------------------------------------------------------------------------------------
   IV. CONTRATO DE RESPUESTA (API SPEC)
   ----------------------------------------------------------------------------------------------------
   El procedimiento garantiza retornar siempre un resultado legible, evitando que el Frontend 
   tenga que lidiar con excepciones crípticas de la base de datos.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarModalidadCapacitacionFisico`$$

CREATE PROCEDURE `SP_EliminarModalidadCapacitacionFisico`(
    /* -----------------------------------------------------------------
       PARÁMETRO DE ENTRADA (INPUT)
       El identificador único que será el objetivo de la purga.
       ----------------------------------------------------------------- */
    IN _Id_Modalidad INT 
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ESTADO Y CONTROL
       Propósito: Reservar espacio en memoria para los diagnósticos de integridad.
       ======================================================================================== */
    
    /* [Snapshot de Identidad]:
       Almacenamos el nombre antes de borrarlo para poder informarlo en el mensaje de éxito. */
    DECLARE v_Nombre_Modalidad VARCHAR(255) DEFAULT NULL;
    
    /* [Semáforo de Integridad]:
       Contador forense para medir el uso histórico del registro en el sistema operativo. */
    DECLARE v_Referencias_Historicas INT DEFAULT 0;

    /* [Bandera de Existencia]:
       Variable booleana auxiliar para el bloqueo pesimista. */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: HANDLERS DE EMERGENCIA (THE SAFETY NET)
       Propósito: Capturar errores nativos del motor InnoDB y darles un tratamiento humano.
       ======================================================================================== */
    
    /* [1.1] Handler para Error 1451 (Cannot delete or update a parent row: a foreign key constraint fails)
       Este es el cinturón de seguridad de la base de datos. Si nuestra validación lógica (Bloque 4) 
       fallara o si se agregaran nuevas tablas en el futuro sin actualizar este SP, el motor de BD 
       bloqueará el borrado. Este handler captura ese evento, deshace la transacción y da feedback. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Crucial: Liberar cualquier lock adquirido.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE MOTOR [1451]: Integridad Referencial Estricta detectada. La base de datos impidió la eliminación física porque existen vínculos en tablas del sistema (FK) no contempladas en la validación de negocio.'; 
    END;

    /* [1.2] Handler Genérico (Catch-All Exception)
       Objetivo: Capturar cualquier anomalía técnica (disco lleno, pérdida de conexión, etc.). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Reenvía el error original para ser logueado por el Backend.
    END;

    /* ========================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST)
       Propósito: Identificar peticiones inválidas antes de comprometer recursos de servidor.
       ======================================================================================== */
    
    /* 2.1 Validación de Tipado e Integridad de Entrada:
       Un ID nulo o negativo es una anomalía de la aplicación cliente que no debe procesarse. */
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE PROTOCOLO [400]: El Identificador de Modalidad proporcionado es inválido o nulo.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y SECUESTRO DE FILA (X-LOCK)
       Propósito: Aislar el registro objetivo para asegurar que la destrucción sea atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: LECTURA CON BLOQUEO EXCLUSIVO (FOR UPDATE)
       
       Lógica Técnica:
       No basta con un SELECT simple. El uso de `FOR UPDATE` garantiza que:
       1. Si el registro existe, queda bloqueado para lectura/escritura de otros usuarios.
       2. Evitamos que otro Admin lo "use" para crear una capacitación mientras estamos 
          en medio del proceso de borrado.
       ---------------------------------------------------------------------------------------- */
    
    SELECT 1, `Nombre` 
    INTO v_Existe, v_Nombre_Modalidad
    FROM `Cat_Modalidad_Capacitacion`
    WHERE `Id_CatModalCap` = _Id_Modalidad
    LIMIT 1
    FOR UPDATE;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA REAL (IDEMPOTENCIA DE BORRADO)
       Si v_Existe es NULL, el registro ya no existe (pudo ser borrado por otro Admin en paralelo).
       ---------------------------------------------------------------------------------------- */
    IF v_Existe IS NULL THEN
        ROLLBACK; -- Liberamos la transacción.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad que intenta eliminar no existe en el catálogo (probablemente ya fue purgada).';
    END IF;

    /* ========================================================================================
       BLOQUE 4: ANÁLISIS FORENSE DE IMPACTO (HISTORICAL DEPENDENCY SCAN)
       Propósito: Validar que el registro no tenga rastro histórico en la base de datos operativa.
       ======================================================================================== */

    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE LA TABLA DE HECHOS (`DatosCapacitaciones`)
       
       Justificación Forense:
       La tabla `DatosCapacitaciones` es el corazón de la operación. Cualquier vínculo aquí 
       significa que la modalidad fue parte de un proceso de negocio.
       
       Regla Diamante:
       Se utiliza un escaneo TOTAL. No filtramos por `Activo = 1`. 
       Incluso si el curso hijo está borrado lógicamente, la relación física FK persiste en la BD.
       Borrar el padre causaría un error de integridad referencial insalvable.
       ---------------------------------------------------------------------------------------- */
    
    SELECT COUNT(*) INTO v_Referencias_Historicas
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_CatModalCap` = _Id_Modalidad;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: EVALUACIÓN DEL CANDADO DE INTEGRIDAD
       Si el contador es mayor a cero, el registro es INBORRABLE.
       ---------------------------------------------------------------------------------------- */
    IF v_Referencias_Historicas > 0 THEN
        
        ROLLBACK; -- Cancelamos la destrucción. Liberamos los bloqueos de fila.
        
        /* Construimos un mensaje explicativo que guíe al administrador hacia la solución correcta */
        SET @ErrorMsg = CONCAT('BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar físicamente la Modalidad "', v_Nombre_Modalidad, '". Se detectaron ', v_Referencias_Historicas, ' registros históricos que dependen de este identificador. Para proteger la integridad de los reportes y auditorías, utilice la opción de "DESACTIVAR" (Baja Lógica) en su lugar.');
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = @ErrorMsg;
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DE LA PURGA (HARD DELETE)
       Propósito: Eliminar físicamente la fila una vez superados todos los controles de seguridad.
       ======================================================================================== */
    
    /* Si el flujo de ejecución alcanza este punto, el sistema ha certificado bajo lock que:
       1. El registro existe.
       2. El registro es "VIRGEN" (Sin descendencia ni historial).
       3. No hay riesgos de orfandad de datos. */
       
    DELETE FROM `Cat_Modalidad_Capacitacion`
    WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN DE OPERACIÓN Y DESCARGA DE RESPUESTA
       Propósito: Sellar los cambios en el disco y notificar al cliente.
       ======================================================================================== */
    
    /* El comando COMMIT:
       1. Hace permanentes los cambios en los platos del disco duro.
       2. Genera la entrada final en el REDO LOG de la base de datos.
       3. Libera el bloqueo exclusivo (X-Lock), permitiendo que el espacio sea reutilizado por InnoDB. */
    COMMIT;

    /* Retornamos el contrato de salida estructurado para la interfaz de usuario. */
    SELECT 
        CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido eliminada permanentemente y todos sus recursos han sido liberados.') AS Mensaje,
        'ELIMINACION_FISICA_COMPLETA' AS Accion,
        _Id_Modalidad AS Id_Eliminado,
        NOW() AS Timestamp_Ejecucion;

END$$

DELIMITER ;