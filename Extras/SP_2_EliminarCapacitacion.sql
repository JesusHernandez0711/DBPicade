/* ====================================================================================================
   PROCEDIMIENTO: SP_EliminarCapacitacion (HARD DELETE / BORRADO FÍSICO)_
   ====================================================================================================
   
   1. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------
   - Nombre Oficial:      SP_EliminarCapacitacion
   - Clasificación:       Operación Destructiva de Alto Riesgo (High-Risk Destructive Operation).
   - Tipo:                Physical Delete (DELETE FROM...).
   - Nivel de Seguridad:  CRÍTICO (Requiere validación de "Hoja Limpia").
   - Aislamiento:         Serializable (vía Pessimistic Locking).

   2. PROPÓSITO Y REGLAS DE NEGOCIO (BUSINESS RULES)
   -------------------------------------------------
   Este procedimiento elimina PERMANENTEMENTE un expediente de capacitación y todo su historial de versiones
   de la base de datos. A diferencia del "Archivado" (Soft Delete), esta acción destruye los datos y
   libera el Folio.
   
   [CASO DE USO EXCLUSIVO]: 
   Corrección de errores de captura inmediata (ej: "Creé el curso duplicado por error hace 5 minutos
   y nadie se ha inscrito aún").

   [REGLA DE INTEGRIDAD ACADÉMICA - "EL ESCUDO DE ALUMNOS"]:
   Es estrictamente PROHIBIDO eliminar un curso si existe al menos un (1) participante vinculado a 
   cualquiera de sus versiones (detalles), ya sean vigentes, pasadas o archivadas.
   
   - Validación: Se escanea la tabla `Capacitaciones_Participantes` a través de todos los hijos.
   - Si hay alumnos: Se ABORTA la operación con Error 409 (Conflicto de Dependencia).
     * Razón: Borrar el curso dejaría huérfanos los registros académicos, diplomas o constancias DC-3.
   
   - Si NO hay alumnos: Se procede a la DESTRUCCIÓN EN CASCADA.
     * Paso 1: Eliminar Hijos (DatosCapacitaciones - Versiones).
     * Paso 2: Eliminar Padre (Capacitaciones - Expediente).

   3. ESTRATEGIA DE CONCURRENCIA (ACID)
   ------------------------------------
   Utiliza `SELECT ... FOR UPDATE` para bloquear el expediente padre al inicio de la transacción.
   Esto evita que, mientras el sistema verifica si hay alumnos, otro usuario inscriba a un alumno
   en el último milisegundo (Race Condition).

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarCapacitacion`$$

CREATE PROCEDURE `SP_EliminarCapacitacion`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Capacitacion INT -- [OBLIGATORIO] ID del Expediente Padre a destruir.
)
THIS_PROC: BEGIN

    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       ======================================================================================== */
    
    /* Variable para almacenar el conteo de alumnos (Dependencias críticas) */
    DECLARE v_Total_Alumnos INT DEFAULT 0; 
    
    /* Variable para almacenar el Folio y mostrarlo en el mensaje de éxito */
    DECLARE v_Folio VARCHAR(50);
    
    /* Bandera de existencia para el bloqueo pesimista */
    DECLARE v_Existe INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       ======================================================================================== */
    
    /* [1.1] Handler de Integridad Referencial (Error 1451)
       Red de seguridad por si existen otras tablas (ej: Evaluaciones, Finanzas) ligadas
       al curso que no validamos manualmente. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; 
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: No se puede eliminar el curso. Existen referencias en tablas periféricas (posiblemente Costos o Evaluaciones) que impiden su destrucción física.'; 
    END;

    /* [1.2] Handler Genérico (Crash Recovery) */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       ======================================================================================== */
    
    /* 2.1 Validación de Input */
    IF _Id_Capacitacion IS NULL OR _Id_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la capacitación es inválido.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INICIO DE TRANSACCIÓN Y BLOQUEO DE SEGURIDAD
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: VERIFICACIÓN DE EXISTENCIA Y BLOQUEO (FOR UPDATE)
       
       Objetivo: "Secuestrar" el registro padre (`Capacitaciones`).
       Efecto: Nadie puede inscribir alumnos, editar versiones o cambiar estatus de este curso
       mientras nosotros realizamos el análisis forense de eliminación.
       ---------------------------------------------------------------------------------------- */
    SELECT 1, `Numero_Capacitacion` 
    INTO v_Existe, v_Folio
    FROM `Capacitaciones`
    WHERE `Id_Capacitacion` = _Id_Capacitacion
    FOR UPDATE;

    /* Validación 404 */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El curso que intenta eliminar no existe o ya fue borrado.';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EL ESCUDO DE INTEGRIDAD (VALIDACIÓN DE DEPENDENCIAS)
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ESCANEO DE "NIETOS" (ALUMNOS/PARTICIPANTES)
       
       Lógica de Negocio:
       Buscamos si existen registros en `Capacitaciones_Participantes` (Nietos) que estén
       vinculados a cualquier `DatosCapacitaciones` (Hijos) que pertenezca a este Padre.
       
       Criterio Estricto:
       NO filtramos por estatus. Si un alumno reprobó hace 2 años en una versión archivada,
       eso cuenta como historia académica y BLOQUEA el borrado.
       ---------------------------------------------------------------------------------------- */
    SELECT COUNT(*) INTO v_Total_Alumnos
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    WHERE `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* [PUNTO DE BLOQUEO]: Si el contador es mayor a 0, detenemos todo. */
    IF v_Total_Alumnos > 0 THEN
        ROLLBACK; -- Liberamos el bloqueo del padre inmediatamente.
        
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [409]: Imposible eliminar. Existen participantes/alumnos registrados en el historial de este curso (incluso en versiones anteriores). Borrarlo destruiría su historial académico. Utilice la opción de "ARCHIVAR" en su lugar.';
    END IF;

    /* ========================================================================================
       BLOQUE 5: EJECUCIÓN DE LA DESTRUCCIÓN (CASCADE DELETE SEQUENCE)
       Si llegamos aquí, el curso está "limpio" (sin alumnos). Procedemos a borrar.
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 5.1: ELIMINAR HIJOS (DETALLES/VERSIONES)
       Borramos primero la tabla hija para respetar la jerarquía de llaves foráneas manual.
       Esto elimina todas las versiones (fechas, instructores anteriores) del curso.
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `DatosCapacitaciones` 
    WHERE `Fk_Id_Capacitacion` = _Id_Capacitacion;

    /* ----------------------------------------------------------------------------------------
       PASO 5.2: ELIMINAR PADRE (EXPEDIENTE MAESTRO)
       Borramos la cabecera administrativa. Esto libera el Folio para ser reutilizado si se desea.
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = _Id_Capacitacion;

    /* ========================================================================================
       BLOQUE 6: CONFIRMACIÓN Y RESPUESTA
       ======================================================================================== */
    
    /* Confirmamos la transacción atómica */
    COMMIT;

    /* Retorno de Feedback al usuario */
    SELECT 
        'ELIMINADO' AS `Estado_Final`,
        CONCAT('El expediente con folio "', v_Folio, '" ha sido eliminado permanentemente del sistema, junto con todo su historial de versiones.') AS `Mensaje`,
        _Id_Capacitacion AS `Id_Eliminado`;

END$$

DELIMITER ;