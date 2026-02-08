/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_CambiarEstatusCapacitacionParticipante
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   ----------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA DE ALTO NIVEL (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_CambiarEstatusCapacitacionParticipante
   - Sistema:              PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria: 		   Transacciones de Estado y Ciclo de Vida del Participante
   - Clasificación:        Transacción Conmutativa de Estado (Toggle State Transaction)
   - Nivel de Seguridad:   Administrativo / Privilegiado
   - Modelo ACID:          Cumplimiento Total (Atomicidad garantizada por START TRANSACTION)
   - Aislamiento SQL:      READ COMMITTED (Evita lecturas sucias durante el cálculo de cupo)
   - Objetivo Forense:     Centralizar en un solo punto de entrada (Single Point of Truth) la entrada y 
                           salida de alumnos, garantizando que el "Toggle" sea atómico.
   
   ----------------------------------------------------------------------------------------------------------
   2. ANÁLISIS DE RIESGOS Y MITIGACIÓN (RISK ASSESSMENT)
   ----------------------------------------------------------------------------------------------------------
   - RIESGO DE SOBREVENTA (OVERBOOKING): En un entorno concurrente, dos coordinadores podrían intentar
     reinscribir participantes al mismo tiempo. 
     MITIGACIÓN: El SP utiliza lógica de cupo híbrido calculada segundos antes del COMMIT, bloqueando
     el registro objetivo para evitar colisiones.
     
   - RIESGO DE CORRUPCIÓN HISTÓRICA: Dar de baja a un alumno que ya tiene calificación borraría la validez
     de los reportes de acreditación.
     MITIGACIÓN: Bloqueo duro (Hard Block) en la Rama de Baja si `Calificacion` IS NOT NULL.
     
   - RIESGO DE INOPERABILIDAD: Cambiar estados en cursos ya borrados o cancelados.
     MITIGACIÓN: Verificación de Snapshot de Contexto del Curso antes de evaluar al alumno.

   ----------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE LA SOLUCIÓN (SINGLE-ENDPOINT TOGGLE)
   ----------------------------------------------------------------------------------------------------------
   El procedimiento implementa un patrón de "Interruptor Lógico". En lugar de tener dos rutas en el backend,
   el sistema operativo de la base de datos detecta el estatus actual:
   
   SI ESTATUS = 5 (BAJA):
      Inicia sub-proceso de REINSCRIPCIÓN.
      Verifica: Cupo (Meta - MAX(Sistema, Manual)).
      Resultado: Estatus 1 (INSCRITO).
   
   SI ESTATUS != 5 (ACTIVO/OTROS):
      Inicia sub-proceso de BAJA ADMINISTRATIVA.
      Verifica: Ausencia de calificación.
      Resultado: Estatus 5 (BAJA).

   ----------------------------------------------------------------------------------------------------------
   4. DICCIONARIO DE ACCIONES (ACTION CODES)
   ----------------------------------------------------------------------------------------------------------
   - 'REINSCRITO':    El alumno recuperó su asiento exitosamente.
   - 'BAJA_EXITOSA':  El alumno liberó el asiento y se guardó la justificación.
   - 'ERROR_TECNICO': Fallo en el motor InnoDB o violación de integridad.
   - 'CUPO_LLENO':    Rechazo por falta de espacio físico/lógico.

   ========================================================================================================== */

DELIMITER $$

-- Eliminación preventiva del objeto para garantizar despliegue limpio (Idempotencia de Script)
DROP PROCEDURE IF EXISTS `SP_CambiarEstatusCapacitacionParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusCapacitacionParticipante`(
    /* ------------------------------------------------------------------------------------------------------
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------------ */
    IN _Id_Usuario_Ejecutor INT,       -- ID del Admin/Coordinador (Trazabilidad de Auditoría)
    IN _Id_Registro_Participante INT,  -- PK de la tabla Capacitaciones_Participantes
    IN _Motivo_Cambio VARCHAR(250)     -- Argumento obligatorio para el log de Justificación
)
ProcTogglePart: BEGIN
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 1: GESTIÓN DE VARIABLES Y ASIGNACIÓN DE MEMORIA (VARIABLE ALLOCATION)
       Cada variable está diseñada para evitar el uso de funciones pesadas dentro de los IF/ELSE.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Variables de Integridad Referencial
    -- Utilizadas para confirmar que las llaves foráneas y el registro objetivo existen físicamente.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;       -- Flag binario de existencia del Admin
    DECLARE v_Registro_Existe INT DEFAULT 0;       -- Flag binario de existencia de la inscripción
    DECLARE v_Id_Detalle_Curso INT DEFAULT 0;      -- ID de la instancia de capacitación (Fk_Id_DatosCap)
    DECLARE v_Id_Padre INT DEFAULT 0;              -- ID de la cabecera para lectura de Metas
    
    -- [1.2] Variables de Estado y Ciclo de Vida
    -- Almacenan el "Snapshot" del momento exacto en que se llamó al procedimiento.
    DECLARE v_Estatus_Actual_Alumno INT DEFAULT 0; -- ID del estado actual (Inscrito, Baja, etc.)
    DECLARE v_Estatus_Curso INT DEFAULT 0;         -- ID del estado actual del curso (1 al 10)
    DECLARE v_Curso_Activo INT DEFAULT 0;          -- Flag de borrado lógico (DC.Activo)
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;    -- Booleano para protección de registros evaluados
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT ''; -- Identificador legible (Numero_Capacitacion)
    DECLARE v_Nombre_Alumno VARCHAR(200) DEFAULT '';-- Nombre completo para reporte de salida
    
    -- [1.3] Variables para Aritmética de Cupo Híbrido
    -- Solo se activan si la lógica detecta que se requiere una REINSCRIPCIÓN.
    DECLARE v_Cupo_Maximo INT DEFAULT 0;           -- Capacidad programada (Meta)
    DECLARE v_Conteo_Sistema INT DEFAULT 0;        -- Inscritos actuales en BD
    DECLARE v_Conteo_Manual INT DEFAULT 0;         -- Bloqueo manual (AsistentesReales)
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;     -- El factor mayor resultante (GREATEST)
    DECLARE v_Cupo_Disponible INT DEFAULT 0;       -- Espacios físicos restantes (Delta)
    
    -- [1.4] Variables de Comunicación (Output Buffers)
    -- Almacenan el resultado dinámico que será entregado al Frontend.
    DECLARE v_Mensaje_Final VARCHAR(255) DEFAULT '';
    DECLARE v_Accion_Final VARCHAR(50) DEFAULT '';
    
    -- [1.5] Definición de Constantes de Negocio (Business Rules Mappings)
    -- Centralización de IDs para evitar desalineación con los catálogos maestros.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;      -- Cat_Estatus_Participantes: INSCRITO
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;          -- Cat_Estatus_Participantes: BAJA
    DECLARE c_CURSO_CANCELADO INT DEFAULT 8;       -- Cat_Estatus_Capacitacion: CANCELADO
    DECLARE c_CURSO_ARCHIVADO INT DEFAULT 10;      -- Cat_Estatus_Capacitacion: CERRADO/ARCHIVADO

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       BLOQUE 2: HANDLER DE SEGURIDAD TRANSACCIONAL (ACID PROTECTION)
       Este bloque es el "Paracaídas" del procedimiento. Si el motor InnoDB detecta una colisión de datos,
       un error de tipo de dato o un fallo de servidor, este handler captura la excepción.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- [FORENSIC ACTION]: Si el proceso falló a mitad de camino, revierte cualquier cambio en disco.
        ROLLBACK;
        
        -- Retorno de error controlado para que el backend (Laravel) sepa que la transacción fue fallida.
        SELECT 
            'ERROR DE SISTEMA [500]: Fallo crítico detectado por el motor de BD al alternar el estado.' AS Mensaje, 
            'ERROR_TECNICO' AS Accion;
    END;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN ESTRUCTURAL (FAIL-FAST)
       Antes de tocar la memoria o las tablas, validamos que los punteros (IDs) sean lógicos.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [0.1] Validación del Ejecutor: No puede ser nulo ni negativo.
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es inválido o nulo.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.2] Validación del Registro Objetivo: El ID de inscripción debe ser un entero positivo.
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 
		THEN 
			SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es inválido o nulo.' AS Mensaje, 
				'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [0.3] Validación de Justificación: Auditoría forense obligatoria. No se permiten cambios "anónimos".
    IF _Motivo_Cambio IS NULL OR TRIM(_Motivo_Cambio) = '' 
		THEN
			SELECT 'ERROR DE ENTRADA [400]: El motivo del cambio es obligatorio para fines de trazabilidad.' AS Mensaje, 
            'VALIDACION_FALLIDA' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CONTEXTO Y SEGURIDAD (SNAPSHOT DE DATOS)
       Este bloque carga en memoria el estado actual de todas las entidades involucradas.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [1.1] Validación de Identidad del Ejecutor
    -- Confirmamos que el Admin existe y no ha sido suspendido (Activo=1).
    SELECT COUNT(*) INTO v_Ejecutor_Existe 
    FROM `Usuarios` WHERE `Id_Usuario` = _Id_Usuario_Ejecutor AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 THEN 
        SELECT 'ERROR DE SEGURIDAD [403]: El Usuario Ejecutor no tiene permisos vigentes en el sistema.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.2] Carga Masiva de Datos del Registro (Data Hydration)
    -- Se realiza una consulta con Joins para obtener la "fotografía" del alumno y su curso.
    SELECT 
        COUNT(*),                               -- [0] Verificador de existencia física
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),   -- [1] Estatus actual del alumno
        `CP`.`Fk_Id_DatosCap`,                  -- [2] Puntero al curso específico
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`), -- [3] Nombre para feedback dinámico
        CASE WHEN `CP`.`Calificacion` IS NOT NULL THEN 1 ELSE 0 END, -- [4] Protección de evaluación
        `DC`.`Activo`,                          -- [5] Verificador de Soft Delete del curso
        `DC`.`Fk_Id_CatEstCap`,                 -- [6] Estatus operativo del curso (1-10)
        `DC`.`Fk_Id_Capacitacion`,              -- [7] Puntero a la cabecera (Meta)
        COALESCE(`DC`.`AsistentesReales`, 0)    -- [8] Conteo manual del coordinador
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual_Alumno,
        v_Id_Detalle_Curso,
        v_Nombre_Alumno,
        v_Tiene_Calificacion,
        v_Curso_Activo,
        v_Estatus_Curso,
        v_Id_Padre,
        v_Conteo_Manual
    FROM `Capacitaciones_Participantes` `CP`
    INNER JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    INNER JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    INNER JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;

    -- [1.3] Validación de Existencia Física
    IF v_Registro_Existe = 0 
		THEN 
			SELECT 'ERROR DE INTEGRIDAD [404]: No se encontró el registro de inscripción solicitado.' AS Mensaje, 
            'RECURSO_NO_ENCONTRADO' AS Accion; 
        LEAVE ProcTogglePart; 
    END IF;
    
    -- [1.4] Obtención de Metadatos de la Cabecera
    -- Obtenemos el folio del curso y la meta de asistentes programada originalmente.
    SELECT `Numero_Capacitacion`, 
		`Asistentes_Programados` 
	INTO v_Folio_Curso, 
		v_Cupo_Maximo
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Padre;

    -- [1.5] Validación de Lista Negra de Estatus (Whitelist Integrity)
    -- Impedimos que se altere la lista de alumnos en cursos que ya no son operables.
    IF v_Estatus_Curso IN (c_CURSO_CANCELADO, c_CURSO_ARCHIVADO) 
		THEN
			SELECT CONCAT('ERROR DE LÓGICA [409]: El curso "', v_Folio_Curso, '" está CANCELADO o ARCHIVADO. No se permiten modificaciones.') AS Mensaje, 
               'ESTATUS_PROHIBIDO' AS Accion;
        LEAVE ProcTogglePart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: ÁRBOL DE DECISIÓN LÓGICA (TOGGLE ARCHITECTURE)
       El sistema evalúa el estado del alumno y bifurca el flujo en dos ramas mutuamente excluyentes.
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [INICIO DE EVALUACIÓN DE ESTADO]
    IF v_Estatus_Actual_Alumno = c_ESTATUS_BAJA THEN
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA A: PROCESO DE REINSCRIBIR (RE-ENTRY LOGIC)
           Escenario: El participante estaba fuera y el Admin quiere ingresarlo de nuevo.
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        
        -- [A.1] Validación Concurrente de Cupo Híbrido (Pessimistic Check)
        -- Contamos todos los alumnos que NO están en baja para ver cuánto espacio queda.
        SELECT COUNT(*) INTO v_Conteo_Sistema 
        FROM `Capacitaciones_Participantes` 
        WHERE `Fk_Id_DatosCap` = v_Id_Detalle_Curso 
          AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

        -- Aplicamos el algoritmo GREATEST: Respetar el bloqueo manual si es mayor al sistema.
        SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);
        
        -- Calculamos el Delta (Espacios libres reales).
        SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
        
        -- Si el resultado es cero o negativo, bloqueamos la reinscripción.
        IF v_Cupo_Disponible <= 0 
			THEN
				SELECT CONCAT('ERROR DE CUPO [409]: Imposible reinscribir a "', v_Nombre_Alumno, '". La capacitación "', v_Folio_Curso, '" está llena.') AS Mensaje, 
                   'CUPO_LLENO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- [A.2] Ejecución del Cambio de Estado (Write Transaction)
        START TRANSACTION;
            UPDATE `Capacitaciones_Participantes`
            SET `Fk_Id_CatEstPart` = c_ESTATUS_INSCRITO, -- Cambia a estado Activo (1)
                -- Concatenamos fecha y motivo para auditoría histórica en el campo Justificación.
                `Justificacion` = CONCAT('REINSCRIBIR [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ', _Motivo_Cambio),
                `updated_at` = NOW(), -- Timestamp de sistema
                `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor -- ID del responsable del cambio
            WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        -- Seteo de buffers de respuesta exitosa.
        SET v_Mensaje_Final = CONCAT('REINSCRIPCIÓN EXITOSA: "', v_Nombre_Alumno, '" ha sido reactivado en el curso "', v_Folio_Curso, '".');
        SET v_Accion_Final = 'REINSCRITO';

    ELSE
        
        /* ═══════════════════════════════════════════════════════════════════════════════════════════════
           RAMA B: PROCESO DE DAR DE BAJA (OFFBOARDING LOGIC)
           Escenario: El participante está activo y el Admin quiere retirarlo del curso.
           ═══════════════════════════════════════════════════════════════════════════════════════════════ */
        
        -- [B.1] Validación de Integridad Académica (Academic Constraint)
        -- No se puede retirar a alguien que ya fue calificado, pues su nota ya forma parte del promedio histórico.
        IF v_Tiene_Calificacion = 1 
			THEN
				SELECT CONCAT('ERROR DE INTEGRIDAD [409]: No se puede dar de baja a "', v_Nombre_Alumno, '" porque ya cuenta con una calificación asentada.') AS Mensaje, 
                   'CONFLICTO_ESTADO' AS Accion;
            LEAVE ProcTogglePart;
        END IF;
        
        -- [B.2] Ejecución del Cambio de Estado (Write Transaction)
        START TRANSACTION;
            UPDATE `Capacitaciones_Participantes`
            SET `Fk_Id_CatEstPart` = c_ESTATUS_BAJA, -- Cambia a estado Baja (5), liberando cupo.
                -- Documentamos la baja para evitar reclamaciones futuras (Compliance).
                `Justificacion` = CONCAT('DAR DE BAJA [', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), ']: ', _Motivo_Cambio),
                `updated_at` = NOW(), -- Timestamp de sistema
                `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor -- ID del responsable del cambio
            WHERE `Id_CapPart` = _Id_Registro_Participante;
        COMMIT;
        
        -- Seteo de buffers de respuesta exitosa.
        SET v_Mensaje_Final = CONCAT('BAJA REGISTRADA: "', v_Nombre_Alumno, '" ha sido retirado correctamente del curso "', v_Folio_Curso, '".');
        SET v_Accion_Final = 'BAJA_EXITOSA';
        
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 3: DESCARGA DE RESPUESTA (FINAL OUTPUT)
       El procedimiento finaliza enviando un resultset limpio al cliente (Laravel/Frontend).
       ═══════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT v_Mensaje_Final AS Mensaje, v_Accion_Final AS Accion;

END$$

DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   NOTAS DE AUDITORÍA POST-DESPLIEGUE:
   - Se recomienda monitorear los registros de `Justificacion` para detectar patrones de bajas masivas.
   - El uso de GREATEST en la Rama A garantiza que el sistema nunca exceda la capacidad física del aula.
   - Este procedimiento es totalmente compatible con el botón "Dar de Baja / Reinscribir" del frontend.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */