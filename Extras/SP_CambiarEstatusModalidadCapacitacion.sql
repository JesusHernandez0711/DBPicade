/* ====================================================================================================
   PROCEDIMIENTO ALMACENADO: SP_CambiarEstatusModalidadCapacitacion
   ====================================================================================================
   
   ----------------------------------------------------------------------------------------------------
   I. RESUMEN EJECUTIVO Y CONTEXTO DE NEGOCIO (EXECUTIVE SUMMARY)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este procedimiento actúa como el "Interruptor Maestro de Disponibilidad" (Availability Toggle) para 
   el catálogo de Modalidades de Capacitación. Su función no es simplemente actualizar una columna 
   booleana; es un orquestador de integridad que decide si es seguro retirar un recurso del ecosistema.

   [EL RIESGO OPERATIVO (THE BUSINESS RISK)]:
   En un sistema de gestión de capacitación (LMS), la "Modalidad" no es un dato decorativo; es un 
   eje estructural. Define la logística, los recursos necesarios (salas vs licencias Zoom) y las 
   reglas de asistencia.
   
   Escenario Catastrófico:
   1. Un Administrador desactiva la modalidad "VIRTUAL" un lunes a las 09:00 AM.
   2. Existen 50 cursos programados para iniciar esa semana bajo esa modalidad.
   3. Resultado: Los instructores no pueden registrar asistencia, los reportes de cumplimiento fallan 
      por "Modalidad Nula/Inválida", y la operación se detiene.

   [LA SOLUCIÓN ARQUITECTÓNICA (THE SOLUTION)]:
   Implementamos un patrón de diseño llamado "Safe Soft Delete" (Baja Lógica Segura).
   El sistema realiza un análisis de impacto en tiempo real antes de permitir la desactivación.
   Si detecta dependencias vivas, bloquea la acción y protege la continuidad del negocio.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (SECURITY & INTEGRITY RULES)
   ----------------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD REFERENCIAL DESCENDENTE (DOWNSTREAM INTEGRITY):
      - Principio: "Un padre no puede morir si sus hijos dependen de él para vivir".
      - Regla Técnica: No se permite establecer `Activo = 0` si existen registros en la tabla 
        `DatosCapacitaciones` que cumplan dos condiciones simultáneas:
          a) Estén vinculados a esta Modalidad (`Fk_Id_CatModalCap`).
          b) Tengan un estatus operativo VIGENTE (`Activo = 1`).
      - Excepción: Si los cursos históricos ya están "muertos" (Cancelados/Finalizados/Borrados), 
        el bloqueo no aplica. Esto permite la depuración del catálogo a largo plazo.

   [RN-02] IDEMPOTENCIA DE ESTADO (STATE IDEMPOTENCY):
      - Principio: "No arregles lo que no está roto".
      - Regla Técnica: Si el sistema recibe una solicitud para cambiar el estatus al valor que YA tiene 
        actualmente (ej: Activar una modalidad Activa), el procedimiento aborta la escritura y retorna 
        un mensaje de éxito informativo.
      - Beneficio: 
          1. Reducción de I/O en disco (no hay UPDATE).
          2. Preservación de la auditoría (no se altera `updated_at` artificialmente).
          3. Menor bloqueo de filas (mayor concurrencia).

   [RN-03] ATOMICIDAD TRANSACCIONAL (ACID COMPLIANCE):
      - Principio: "Todo o Nada".
      - Mecanismo: La lectura de verificación y la escritura del cambio ocurren dentro de una 
        transacción aislada con nivel SERIALIZABLE (vía `FOR UPDATE`).
      - Justificación: Evita la "Condición de Carrera del Milisegundo" (Race Condition), donde un 
        usuario crea un curso nuevo justo en el instante entre la validación y la desactivación.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA DE ALTO NIVEL (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Stored Procedure Transaccional (InnoDB).
   - AISLAMIENTO: Pessimistic Locking (Bloqueo Pesimista).
   - INPUT: 
       * _Id_Modalidad (INT): Identificador único.
       * _Nuevo_Estatus (TINYINT): Flag binario (0/1).
   - OUTPUT: Resultset JSON-Friendly { Mensaje, Accion, Estado_Nuevo, Estado_Anterior }.
   - ERRORES CONTROLADOS: 
       * 400 (Bad Request): Datos de entrada inválidos.
       * 404 (Not Found): Recurso inexistente.
       * 409 (Conflict): Bloqueo por reglas de negocio.
       * 500 (Internal Server Error): Fallos de SQL.

   ----------------------------------------------------------------------------------------------------
   IV. MAPA DE MEMORIA Y VARIABLES (MEMORY ALLOCATION)
   ----------------------------------------------------------------------------------------------------
   El procedimiento reserva espacio para:
      - Snapshots del registro actual (para comparar antes/después).
      - Contadores de dependencias (para la lógica de bloqueo).
      - Banderas de control de flujo.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusModalidadCapacitacion`$$

CREATE PROCEDURE `SP_CambiarEstatusModalidadCapacitacion`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos desde el controlador del Backend.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Modalidad INT,        -- [OBLIGATORIO] Identificador del recurso a modificar.
    IN _Nuevo_Estatus TINYINT    -- [OBLIGATORIO] 1 = Activar, 0 = Desactivar.
)
THIS_PROC: BEGIN
    
    /* ================================================================================================
       BLOQUE 0: INICIALIZACIÓN DE VARIABLES DE ESTADO
       Propósito: Definir los contenedores en memoria para la lógica del procedimiento.
       ================================================================================================ */
    
    /* [Snapshot del Estado Actual]:
       Almacenamos cómo está el registro en la BD antes de tocarlo. 
       Vital para la verificación de idempotencia y para el mensaje de respuesta. */
    DECLARE v_Estatus_Actual TINYINT(1) DEFAULT NULL;
    DECLARE v_Nombre_Modalidad VARCHAR(255) DEFAULT NULL;
    
    /* [Semáforo de Dependencias]:
       Contador utilizado para escanear la tabla `DatosCapacitaciones`.
       Si este valor es > 0, significa que hay hijos vivos y debemos activar el bloqueo. */
    DECLARE v_Dependencias_Activas INT DEFAULT 0;

    /* [Bandera de Existencia]:
       Variable auxiliar para confirmar si el ID proporcionado es válido. */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ================================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (ERROR HANDLING)
       Propósito: Garantizar que la base de datos nunca quede en un estado inconsistente.
       ================================================================================================ */
    
    /* Handler Genérico (Catch-All):
       Ante cualquier error SQL inesperado (Deadlock, Conexión perdida, Corrupción de índice),
       este bloque se activa automáticamente para:
         1. Revertir cualquier cambio pendiente (ROLLBACK).
         2. Propagar el error original al cliente (RESIGNAL). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ================================================================================================
       BLOQUE 2: PROTOCOLO DE VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Rechazar peticiones malformadas ("Basura") antes de consumir recursos.
       ================================================================================================ */
    
    /* 2.1 Validación de Dominio (Type Safety):
       El estatus es un valor booleano lógico. Solo aceptamos 0 o 1.
       Cualquier otro valor (ej: 2, 99, -1) indica un error en la capa de aplicación. */
    IF _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El parámetro _Nuevo_Estatus solo acepta valores binarios: 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* 2.2 Validación de Identidad (Integrity Check):
       El ID debe ser un entero positivo. */
    IF _Id_Modalidad IS NULL OR _Id_Modalidad <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Modalidad es inválido o nulo.';
    END IF;

    /* ================================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO PESIMISTA
       El núcleo de la seguridad transaccional. Aquí aislamos el proceso del resto del mundo.
       ================================================================================================ */
    START TRANSACTION;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.1: LECTURA Y BLOQUEO DEL RECURSO (SNAPSHOT ACQUISITION)
       
       Mecánica Técnica:
       Ejecutamos un SELECT con la cláusula `FOR UPDATE`.
       
       Efecto en el Motor de Base de Datos (InnoDB):
       1. Localiza la fila específica en el índice primario (`Id_CatModalCap`).
       2. Coloca un "Exclusive Lock (X-Lock)" sobre esa fila.
       3. Cualquier otra transacción que intente leer o escribir en ESTA fila entrará en 
          estado de espera (WAIT) hasta que nosotros hagamos COMMIT o ROLLBACK.
       
       Justificación de Negocio:
       Evita que otro administrador edite el nombre de la modalidad o la borre físicamente
       mientras nosotros estamos evaluando si es seguro desactivarla.
       ------------------------------------------------------------------------------------------------ */
    SELECT `Activo`, `Nombre` 
    INTO v_Estatus_Actual, v_Nombre_Modalidad
    FROM `Cat_Modalidad_Capacitacion` 
    WHERE `Id_CatModalCap` = _Id_Modalidad 
    LIMIT 1
    FOR UPDATE;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.2: VALIDACIÓN DE EXISTENCIA (NOT FOUND HANDLER)
       Si la variable v_Estatus_Actual sigue siendo NULL, significa que el SELECT no encontró nada.
       El registro no existe (Error 404).
       ------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Actual IS NULL THEN
        ROLLBACK; -- Liberamos recursos aunque no haya locks efectivos.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La Modalidad solicitada no existe en el catálogo maestro.';
    END IF;

    /* ------------------------------------------------------------------------------------------------
       PASO 3.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN DE RECURSOS)
       
       Concepto:
       Una operación es idempotente si realizarla múltiples veces tiene el mismo efecto que una sola vez.
       
       Lógica Aplicada:
       Si el usuario pide "ACTIVAR" una modalidad que ya está "ACTIVA", no hay cambio de estado.
       Por lo tanto, no hay necesidad de ejecutar un UPDATE.
       
       Beneficios:
       1. Ahorro de I/O de disco (escritura).
       2. Ahorro de espacio en logs de transacción.
       3. Integridad de Auditoría: No se modifica la fecha `updated_at` falsamente.
       ------------------------------------------------------------------------------------------------ */
    IF v_Estatus_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo inmediatamente.
        
        /* Retornamos un mensaje de éxito informativo pero aclaratorio */
        SELECT CONCAT('AVISO: La Modalidad "', v_Nombre_Modalidad, '" ya se encuentra en el estado solicitado (', IF(_Nuevo_Estatus=1,'ACTIVO','INACTIVO'), ').') AS Mensaje, 
               'SIN_CAMBIOS' AS Accion,
               v_Estatus_Actual AS Estado_Anterior,
               _Nuevo_Estatus AS Estado_Nuevo;
        
        LEAVE THIS_PROC; -- Salimos del procedimiento limpiamente.
    END IF;

    /* ================================================================================================
       BLOQUE 4: EVALUACIÓN DE REGLAS DE BLINDAJE (CANDADOS DE INTEGRIDAD)
       Solo ejecutamos este análisis profundo si realmente vamos a cambiar el estado.
       ================================================================================================ */

    /* ------------------------------------------------------------------------------------------------
       PASO 4.1: CANDADO OPERATIVO DESCENDENTE (SOLO AL DESACTIVAR)
       
       Contexto:
       Desactivar (`_Nuevo_Estatus = 0`) es una operación destructiva lógica. Puede dejar huérfanos.
       Activar (`_Nuevo_Estatus = 1`) es una operación segura (generalmente).
       
       Por tanto, este bloque solo se ejecuta si la intención es APAGAR el recurso.
       ------------------------------------------------------------------------------------------------ */
    IF _Nuevo_Estatus = 0 THEN
        
        /* [ANÁLISIS DE DEPENDENCIAS]:
           Consultamos la tabla operativa `DatosCapacitaciones`.
           Esta tabla contiene el historial de todos los cursos impartidos.
           
           Criterios de Búsqueda:
           1. `Fk_Id_CatModalCap` = ID de la modalidad actual.
           2. `Activo` = 1.
           
           ¿Por qué `Activo = 1`?
           Porque solo nos preocupan los cursos VIVOS. Si un curso fue cancelado o eliminado
           lógicamente en el pasado, no representa un conflicto para desactivar la modalidad hoy.
           Pero si el curso está programado, en curso o finalizado (sin borrar), es una dependencia dura. */
        
        SELECT COUNT(*) INTO v_Dependencias_Activas
        FROM `DatosCapacitaciones`
        WHERE `Fk_Id_CatModalCap` = _Id_Modalidad
          AND `Activo` = 1; -- Solo nos importan los cursos vigentes.

        /* [DISPARADOR DE BLOQUEO DE INTEGRIDAD]:
           Si el contador es mayor a 0, significa que hay al menos un curso que depende de esta modalidad.
           La operación es ILEGAL bajo las reglas de negocio. */
        IF v_Dependencias_Activas > 0 THEN
            
            ROLLBACK; -- Cancelamos la operación. Se liberan los locks. Ningún dato fue tocado.
            
            /* Retornamos un error 409 (Conflicto) claro y explicativo para el usuario */
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Operación Denegada. No se puede desactivar esta Modalidad porque existen CAPACITACIONES ACTIVAS que dependen de ella. Para proceder, primero debe finalizar, cancelar o reasignar los cursos asociados.';
        END IF;
    END IF;

    /* ================================================================================================
       BLOQUE 5: PERSISTENCIA (EJECUCIÓN DEL CAMBIO)
       Si el flujo llega a este punto, significa que:
         1. El registro existe.
         2. El cambio es necesario (no es idempotente).
         3. No viola ninguna regla de integridad referencial.
       Es seguro escribir en el disco.
       ================================================================================================ */
    
    UPDATE `Cat_Modalidad_Capacitacion` 
    SET `Activo` = _Nuevo_Estatus, 
        `updated_at` = NOW() -- Auditoría: Registramos el momento exacto del cambio.
    WHERE `Id_CatModalCap` = _Id_Modalidad;

    /* ================================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA FINAL
       Propósito: Cerrar la transacción y comunicar el resultado al cliente.
       ================================================================================================ */
    
    /* Confirmamos la transacción (COMMIT).
       Esto hace permanentes los cambios en el disco y libera el bloqueo de la fila,
       permitiendo que otros usuarios vuelvan a leer/escribir este registro. */
    COMMIT;

    /* Generamos la respuesta estructurada para el Frontend.
       Usamos lógica condicional para dar un mensaje humano ("Reactivada" vs "Desactivada"). */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido REACTIVADA y está disponible para nuevas asignaciones.')
            ELSE CONCAT('ÉXITO: La Modalidad "', v_Nombre_Modalidad, '" ha sido DESACTIVADA (Baja Lógica) correctamente.')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        v_Estatus_Actual AS Estado_Anterior,
        _Nuevo_Estatus AS Estado_Nuevo;

END$$

DELIMITER ;