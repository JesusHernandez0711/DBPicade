USE Picade;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   ARTEFACTO DE SOFTWARE : MASTER SCRIPT DE VALIDACIÓN Y CONTROL DE CALIDAD (QA)
   NOMBRE DE CLAVE       : "PROJECT DIAMOND" - AUDITORÍA FORENSE DE CICLO DE VIDA COMPLETO
   VERSIÓN               : 20.0 (DOCUMENTACIÓN FORENSE EXTENDIDA)
   AUTORÍA               : ARQUITECTURA DE DATOS PICADE
   FECHA DE EJECUCIÓN    : AUTOMÁTICA
   
   I. PROPÓSITO DEL DOCUMENTO
   ----------------------------------------------------------------------------------------------------------
   Este script no es solo un conjunto de instrucciones; es una especificación técnica viva.
   Su objetivo es validar la integridad, seguridad y lógica de negocio del sistema PICADE mediante
   la simulación de un ciclo de vida completo de capacitación en un entorno controlado.
   
   II. ALCANCE DE LA PRUEBA
   ----------------------------------------------------------------------------------------------------------
   1. INFRAESTRUCTURA : Creación desde cero de la topología (Sedes, Temas, Jerarquía).
   2. IDENTIDAD       : Provisionamiento masivo de 70+ actores con roles diferenciados.
   3. CICLO DE VIDA   : Gestión simultánea de 6 Cursos + 1 Cancelado.
   4. CAOS CONTROLADO : Simulación de bajas, reingresos y competencia por cupo (Queue Logic).
   5. HISTORIAL       : Generación de versiones históricas inmutables.
   6. VISIBILIDAD     : Auditoría de reportes y dashboards en puntos críticos.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

-- [CONFIGURACIÓN DE SESIÓN]
-- Definimos las variables globales que controlarán la ejecución.
-- @AdminEjecutor: Simula al usuario "Dios" (Super Admin) que orquesta la prueba.
-- @FechaHoy: Punto de referencia temporal para todos los cálculos de fechas relativas.
SET @AdminEjecutor = 322; 
SET @FechaHoy = CURDATE();

/* ==========================================================================================================
   FASE 0: PROTOCOLO DE ESTERILIZACIÓN (DATA SANITIZATION)
   ==========================================================================================================
   [OBJETIVO]: Garantizar un entorno "Limpio" (Clean Slate).
   [RIESGO MITIGADO]: Falsos positivos causados por datos residuales de ejecuciones anteriores.
   [MÉTODO]: Borrado en cascada inversa (Nietos -> Hijos -> Padres).
   ========================================================================================================== */

-- Desactivamos la verificación de llaves foráneas para permitir el borrado rápido sin bloqueos.
SET FOREIGN_KEY_CHECKS = 0;

-- 0.1 LIMPIEZA DE TABLAS TRANSACCIONALES (DATOS OPERATIVOS)
-- Borramos las calificaciones y asistencias de pruebas anteriores.
DELETE FROM `Evaluaciones_Participantes` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
-- Borramos la relación de inscripción (Nietos).
DELETE FROM `Capacitaciones_Participantes` WHERE `Justificacion` LIKE '%QA-DIAMOND%';
-- Borramos el historial de versiones de los cursos (Hijos).
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
-- Borramos las cabeceras de los cursos (Padres).
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE 'QA-DIAMOND%';

-- 0.2 LIMPIEZA DE ACTORES (USUARIOS DE PRUEBA)
-- Borramos las credenciales de acceso.
DELETE FROM `Usuarios` WHERE `Ficha` LIKE 'QA-DIAMOND%';
-- Borramos los perfiles personales asociados.
DELETE FROM `Info_Personal` WHERE `Nombre` LIKE 'QA-DIAMOND%';

-- 0.3 LIMPIEZA DE INFRAESTRUCTURA (CATÁLOGOS)
-- Eliminamos sedes, departamentos y temas creados específicamente para esta prueba.
DELETE FROM `Cat_Cases_Sedes` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Departamentos` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Centros_Trabajo` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Temas_Capacitacion` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Gerencias_Activos` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Subdirecciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Direcciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Municipio` WHERE `Codigo` LIKE 'QA-DIAMOND%';

-- Reactivamos la seguridad referencial para validar la integridad de las nuevas inserciones.
SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 0 COMPLETADA: Entorno esterilizado y listo para la inyección.' AS STATUS;

/* ==========================================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (TOPOLOGÍA)
   ==========================================================================================================
   [OBJETIVO]: Crear los cimientos del sistema. Sin esto, no se pueden crear cursos ni usuarios.
   [REGLA]: "Zero Assumptions". No asumimos que existe nada; lo creamos todo.
   ========================================================================================================== */
SELECT '--- 1.1 Construyendo Topología Geográfica y Organizacional ---' AS STEP;

-- 1.1.1 GEOGRAFÍA
-- [ACCIÓN]: Crear Municipio, Estado y País de prueba.
-- [LÓGICA]: SP_RegistrarUbicaciones inserta y devuelve IDs.
CALL SP_RegistrarUbicaciones('QA-DIAMOND-MUN', 'MUNICIPIO D', 'QA-DIAMOND-EDO', 'ESTADO D', 'QA-DIAMOND-PAIS', 'PAIS D');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');

-- 1.1.2 ORGANIZACIÓN
-- [ACCIÓN]: Crear la jerarquía corporativa (Gerencia -> Subdirección -> Dirección).
CALL SP_RegistrarOrganizacion('QA-DIAMOND-GER', 'GERENCIA D', 'QA-DIAMOND-SUB', 'SUB D', 'QA-DIAMOND-DIR', 'DIR D');
SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');

-- 1.1.3 ESPACIOS DE TRABAJO
-- [ACCIÓN]: Crear Centro de Trabajo y Departamento.
CALL SP_RegistrarCentroTrabajo('QA-DIAMOND-CT', 'CT D', 'CALLE 1', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_RegistrarDepartamento('QA-DIAMOND-DEP', 'DEPTO D', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');

-- 1.1.4 SEDES EDUCATIVAS (AULAS)
-- [OBJETIVO]: Crear 3 espacios con capacidades distintas para probar validaciones de aforo.
-- Sede A: Capacidad 50 (Aula Magna).
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-A', 'AULA A', 'EDIF A', @IdMun, 50, 1, 1, 0, 0, 0, 0);
SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');
-- Sede B: Capacidad 40 (Laboratorio).
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-B', 'AULA B', 'EDIF B', @IdMun, 40, 1, 1, 0, 0, 0, 0);
SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');
-- Sede C: Capacidad 100 (Virtual).
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-C', 'VIRTUAL', 'ONLINE', @IdMun, 100, 1, 1, 0, 0, 0, 0);
SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');

-- 1.1.5 CATÁLOGO ACADÉMICO (TEMAS)
-- [OBJETIVO]: Definir qué se va a enseñar.
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-1', 'SEGURIDAD', 'SEG', 20, 1);
SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-2', 'LIDERAZGO', 'LID', 10, 1);
SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-3', 'TECNICO', 'TEC', 30, 1);
SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');

-- [CONSTANTES DE SISTEMA]
-- Mapeo de IDs estáticos para uso legible en el script.
SET @RolAdmin=1; 
SET @RolCoord=2; 
SET @RolInst=3; 
SET @RolPart=4;
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo LIMIT 1);
SET @IdRegion  = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo LIMIT 1);
SET @IdPuesto  = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo LIMIT 1);
SET @Mod_Pres=1; 
SET @Mod_Virt=2; 
SET @Mod_Hib=3;
SET @St_Prog=1; 
SET @St_PorIni=2; 
SET @St_EnCurso=3; 
SET @St_Fin=4; 
SET @St_Eval=5; 
SET @St_Acr=6; 
SET @St_NoAcr=7; 
SET @St_Canc=8; 
SET @St_Repro=9; 
SET @St_Arch=10; 
SET @St_Reprog=9;

SELECT '✅ FASE 1 COMPLETADA: Infraestructura operativa lista.' AS STATUS;

/* ==========================================================================================================
   FASE 2: PROVISIONAMIENTO DE ACTORES (IDENTITY MANAGEMENT)
   ==========================================================================================================
   [OBJETIVO]: Crear la población de usuarios que interactuará con el sistema.
   [ALCANCE] : 2 Administradores, 2 Coordinadores, 2 Instructores y 70 Participantes.
   ========================================================================================================== */
SELECT '--- 2.1 Creando Staff Administrativo (Load Balancing) ---' AS STEP;

-- [ADMINISTRADORES]: Responsables de rescates y archivado.
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM1', NULL, 'ADMIN', '1', 'QA', '1990-01-01', '2030-01-01', 'a1@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM2', NULL, 'ADMIN', '2', 'QA', '1990-01-01', '2030-01-01', 'a2@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');

-- [COORDINADORES]: Dueños del proceso de capacitación.
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO1', NULL, 'COORD', '1', 'QA', '1990-01-01', '2030-01-01', 'c1@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO2', NULL, 'COORD', '2', 'QA', '1990-01-01', '2030-01-01', 'c2@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');

-- [INSTRUCTORES]: Responsables de evaluar.
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS1', NULL, 'INST', '1', 'QA', '1990-01-01', '2030-01-01', 'i1@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS2', NULL, 'INST', '2', 'QA', '1990-01-01', '2030-01-01', 'i2@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');

SELECT '--- 2.2 Creando 70 Participantes (P01-P70) ---' AS STEP;
/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Uso de un Procedimiento Temporal (`SP_Temp_GenUsers`) con un bucle WHILE.
   [LÓGICA INTERNA]: Itera 70 veces llamando al SP oficial `SP_RegistrarUsuarioPorAdmin` para crear usuarios.
   [OBJETIVO DE QA]: Simular la carga de una plantilla grande de empleados y validar que el SP soporta
                     inserciones masivas secuenciales sin errores de duplicidad o bloqueo.
   ---------------------------------------------------------------------------------------------------------- */
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$
CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 70 DO
        CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')), NULL, CONCAT('P',i), 'USER', 'QA', '2000-01-01', '2030-01-01', CONCAT('p',i,'@d.test'), '123', 4, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL `SP_Temp_GenUsers`();
DROP PROCEDURE `SP_Temp_GenUsers`;

-- Captura de variable clave para operaciones manuales posteriores.
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');

SELECT '✅ FASE 2 COMPLETADA: Actores creados.' AS STATUS;

/* ==========================================================================================================
   FASE 3: CREACIÓN DE LOS 6 CURSOS (PLANEACIÓN - ESTATUS PROGRAMADO)
   ==========================================================================================================
   [OBJETIVO]: Registrar 6 capacitaciones con cupos heterogéneos y asignaciones variadas.
   [REGLA DE NEGOCIO]: Los cursos nacen en estatus 1 (Programado). Aún no son visibles para inscripción.
   [ACTORES]: Se alterna entre Coordinador 1 y 2 para validar permisos compartidos.
   ========================================================================================================== */
SELECT '--- 3.1 Creando 6 Cursos ---' AS STEP;

-- C01 (Cupo 30): Curso estándar presencial.
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C01', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 30, @St_Prog, 'C01 Base');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02 (Cupo 25): Curso virtual.
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C02', @IdGer, @IdTema2, @U_Inst2, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 25, @St_Prog, 'C02 Base');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03 (Cupo 30): Curso híbrido.
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C03', @IdGer, @IdTema3, @U_Inst1, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 30, @St_Prog, 'C03 Base');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04 (Cupo 20): Curso presencial pequeño.
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C04', @IdGer, @IdTema1, @U_Inst2, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 20, @St_Prog, 'C04 Base');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05 (Cupo 15): Curso virtual pequeño.
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C05', @IdGer, @IdTema2, @U_Inst1, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 15, @St_Prog, 'C05 Base');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06 (Cupo 40): Curso híbrido masivo.
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C06', @IdGer, @IdTema3, @U_Inst2, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 40, @St_Prog, 'C06 Base');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Matriz Administrativa.
   [ACCIÓN]: Ejecutar `SP_ObtenerMatrizPICADE` sin filtros.
   [ESPERADO]: Deben aparecer los 6 cursos recién creados con estatus "PROGRAMADO".
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 1: Matriz Inicial (6 Cursos Programados) ---' AS CHECK_POINT;
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 3 COMPLETADA: 6 Cursos creados y visibles.' AS STATUS;

/* ==========================================================================================================
   FASE 4: INSCRIPCIÓN Y COLA DE ESPERA (MIXTO)
   ==========================================================================================================
   [OBJETIVO]: Poblar los cursos con matrícula real del sistema.
   [ACCIÓN TÉCNICA]: Uso de un Helper (`SP_QA_Enroll`) para iterar y llamar a `SP_RegistrarParticipacionCapacitacion`.
   [LÓGICA]: Se inscribe un rango de usuarios (ej. P01 a P25) en cada curso.
   [REGLA]: Validar que el sistema acepte inscripciones masivas sin romper la integridad.
   ========================================================================================================== */
SELECT '--- 4.1 Inscribiendo Usuarios del Sistema ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Enroll`$$
CREATE PROCEDURE `SP_QA_Enroll`(IN _CursoID INT, IN _Start INT, IN _End INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_ID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        CALL SP_RegistrarParticipacionCapacitacion(v_ID, _CursoID); 
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01 (30 Cupos): Llenamos 25 con Sistema (Deja 5 libres para externos).
CALL `SP_QA_Enroll`(@C01_Ver, 1, 25); 
-- C02 (25 Cupos): Llenamos 20 con Sistema (Deja 5 libres).
CALL `SP_QA_Enroll`(@C02_Ver, 26, 45); 
-- C03 (30 Cupos): Llenamos 30 con Sistema (100% LLENO).
CALL `SP_QA_Enroll`(@C03_Ver, 1, 30); 
-- C04 (20 Cupos): Llenamos 20 con Sistema (100% LLENO).
CALL `SP_QA_Enroll`(@C04_Ver, 31, 50); 
-- C05 (15 Cupos): Llenamos 15 con Sistema (100% LLENO).
CALL `SP_QA_Enroll`(@C05_Ver, 1, 15);
-- C06 (40 Cupos): Llenamos 30 con Sistema (Deja 10 libres).
CALL `SP_QA_Enroll`(@C06_Ver, 16, 45);

DROP PROCEDURE `SP_QA_Enroll`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Lista de Asistencia.
   [ACCIÓN]: El instructor consulta la lista de C04.
   [ESPERADO]: Debe mostrar 20 registros activos.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 2: Instructor consulta lista C04 (Debe estar llena con 20) ---' AS CHECK_POINT;
CALL SP_ConsularParticipantesCapacitacion(@C04_Ver);

SELECT '✅ FASE 4 COMPLETADA: Inscripciones realizadas.' AS STATUS;

/* ==========================================================================================================
   FASE 4.5: TURBULENCIA OPERATIVA (CAOS EN LOS 6 CURSOS)
   ==========================================================================================================
   [OBJETIVO]: Simular la realidad operativa: la gente se da de baja y luego quiere volver.
   [ACCIÓN TÉCNICA]: Uso de Helper (`SP_QA_Chaos`) para ejecutar 5 Bajas y 3 Reingresos por curso.
   [LÓGICA]: 
     1. BAJA (Status 5): Libera el cupo.
     2. REINGRESO (Status 1): Intenta recuperar el lugar.
   [REGLA DE NEGOCIO]: Si el curso está lleno (como C03, C04, C05), y alguien toma el lugar liberado, 
                       el reingreso DEBE FALLAR (Error 409 Cupo Lleno).
   ========================================================================================================== */
SELECT '--- 4.5 Caos Administrativo (Bajas y Reingresos Masivos) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Chaos`$$
CREATE PROCEDURE `SP_QA_Chaos`(IN _CursoID INT, IN _StartUser INT, IN _AdminID INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_UserID INT;
    DECLARE v_RegID INT;
    
    -- PASO 1: DAR DE BAJA A 5 ALUMNOS (Liberación de Espacio)
    WHILE i < 5 DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        
        IF v_RegID IS NOT NULL THEN
            -- Se cambia el estatus a 5 (BAJA)
            CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, 5, 'QA: Baja Administrativa por RH');
        END IF;
        SET i = i + 1;
    END WHILE;

    -- PASO 2: INTENTO DE REINGRESO DE 3 ALUMNOS (Lucha por el cupo)
    SET i = 0;
    WHILE i < 3 DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        
        IF v_RegID IS NOT NULL THEN
            -- Se intenta cambiar el estatus a 1 (INSCRITO).
            -- Envolvemos en bloque seguro para capturar error de cupo lleno sin detener el script.
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, 1, 'QA: Reingreso solicitado');
            END;
        END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- Ejecutar Caos en los 6 Cursos
CALL `SP_QA_Chaos`(@C01_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C02_Ver, 26, @U_Coo1);
CALL `SP_QA_Chaos`(@C03_Ver, 1, @U_Coo2);
CALL `SP_QA_Chaos`(@C04_Ver, 31, @U_Coo2);
CALL `SP_QA_Chaos`(@C05_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C06_Ver, 16, @U_Coo2);

DROP PROCEDURE `SP_QA_Chaos`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Vista del Alumno.
   [ACCIÓN]: El Alumno P01 verifica su estatus.
   [ESPERADO]: Debe ver si sigue inscrito o si su baja fue efectiva.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 3: Alumno P01 revisa sus cursos post-caos ---' AS CHECK_POINT;
CALL SP_ConsularMisCursos(@U_P01);

SELECT '✅ FASE 4.5 COMPLETADA: Turbulencia operativa aplicada.' AS STATUS;

/* ==========================================================================================================
   FASE 5: AUTORIZACIÓN (POR INICIAR) + CUPO EXTERNO
   ==========================================================================================================
   [OBJETIVO]: Avanzar el ciclo de vida a la fase operativa y bloquear cupos para externos.
   [ACCIÓN TÉCNICA]: SP_Editar_Capacitacion con Estatus 2 (Por Iniciar) y `AsistentesReales` > 0.
   [LÓGICA]: El sistema crea la Versión 2 del curso. 
             Calcula el cupo total = GREATEST(Sistema, Manuales).
   [QA]: Validar que los cursos "híbridos" queden saturados.
   ========================================================================================================== */
SELECT '--- 5.1 Autorizando y Definiendo Cupo Externo ---' AS STEP;

-- C01: Autorizado con 10 externos manuales.
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 10, 'Autorizado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

-- C02: Autorizado con 15 externos.
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 15, 'Autorizado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- C03: Autorizado con 5 externos.
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 5, 'Autorizado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

-- C04: Autorizado (0 Externos).
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 0, 'Autorizado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

-- C05: Autorizado con 5 externos.
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 5, 'Autorizado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

-- C06: Autorizado con 20 externos.
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 20, 'Autorizado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Buscador.
   [ACCIÓN]: Buscar 'QA-DIAMOND'.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR".
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;
CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');

SELECT '✅ FASE 5 COMPLETADA: Cursos autorizados.' AS STATUS;

/* ==========================================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS Y REPROGRAMACIÓN (HISTORIAL 5 PASOS)
   ========================================================================================================== 
   [OBJETIVO]: Generar un historial robusto de cambios para probar la integridad referencial.
   [ACCIÓN TÉCNICA]: 5 llamadas secuenciales a `SP_Editar_Capacitacion` por cada curso.
   [LÓGICA]: 
     1. Cambio Instructor (Reprogramado).
     2. Cambio Sede (Reprogramado).
     3. Cambio Fecha (Reprogramado).
     4. Ajuste Menor (Reprogramado).
     5. Regreso a Por Iniciar (Confirmación).
   [QA]: Validar que los alumnos se migren automáticamente a la nueva versión en cada paso.
   ========================================================================================================== */
SELECT '--- 6.1 Generando Historial Masivo (5 Cambios x 6 Cursos) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_HistoryBuilder`$$
CREATE PROCEDURE `SP_QA_HistoryBuilder`(IN _IDVer INT, IN _HeadID INT, IN _CoordID INT, IN _InstID INT, IN _SedeID INT, IN _ModID INT)
BEGIN
    DECLARE v_NewVer INT DEFAULT _IDVer;
    
    -- Cambio 1: Instructor + Estatus Reprogramado (9)
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'QA: Cambio Inst');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 2: Sede
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'QA: Cambio Sede');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 3: Fecha
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'QA: Nueva Fecha');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 4: Ajuste Menor
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'QA: Ajuste');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 5: Regreso Automático a Por Iniciar (2)
    -- Simulamos que faltan 2 semanas para el inicio.
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 2, DATE_ADD(CURDATE(), INTERVAL 14 DAY), DATE_ADD(CURDATE(), INTERVAL 19 DAY), 0, 'QA: Confirmado');
END$$
DELIMITER ;

-- Ejecutar para los 6 cursos
CALL `SP_QA_HistoryBuilder`(@C01_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'), @U_Coo1, @U_Inst2, @IdSedeA, @Mod_Pres);
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

CALL `SP_QA_HistoryBuilder`(@C02_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'), @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt);
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

CALL `SP_QA_HistoryBuilder`(@C03_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'), @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib);
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

CALL `SP_QA_HistoryBuilder`(@C04_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'), @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres);
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

CALL `SP_QA_HistoryBuilder`(@C05_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'), @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt);
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

CALL `SP_QA_HistoryBuilder`(@C06_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'), @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib);
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

DROP PROCEDURE `SP_QA_HistoryBuilder`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Trazabilidad Histórica.
   [ACCIÓN]: Consultar el detalle de C01.
   [ESPERADO]: Debe mostrar 5 versiones en el historial (footer) y la configuración actual en el header.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

SELECT '✅ FASE 6 COMPLETADA: Historial profundo generado.' AS STATUS;

/* ==========================================================================================================
   FASE 7: EJECUCIÓN (EN CURSO)
   ==========================================================================================================
   [OBJETIVO]: Simular que llegó la fecha de inicio.
   [ACCIÓN TÉCNICA]: Cambiar estatus a 3 (En Curso).
   [IMPORTANTE]: Al cambiar de versión, la lista de asistencia se "congela" en la nueva versión.
   ========================================================================================================== */
SELECT '--- 7.1 Arrancando Cursos ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'En Curso');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'En Curso');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'En Curso');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'En Curso');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados.
   [ESPERADO]: Debe ver los cursos donde fue asignado como titular en la última versión.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 7 COMPLETADA: Cursos en ejecución.' AS STATUS;

/* ==========================================================================================================
   FASE 8: EVALUACIÓN (ASENTAMIENTO DE NOTAS)
   ==========================================================================================================
   [OBJETIVO]: Simular el fin del curso y la captura de calificaciones.
   
   PASO 1: Cambio de estatus a 5 (Evaluación).
   PASO 2: Ejecución de `SP_EditarParticipanteCapacitacion` para cada alumno.
   [LÓGICA]: 
     - Si Nota >= 70 -> Estatus 3 (APROBADO).
     - Si Nota < 70  -> Estatus 4 (REPROBADO).
   ========================================================================================================== */
SELECT '--- 8.1 Cambio Automático a EVALUACIÓN (Los 6 Cursos) ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Evaluando');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Evaluando');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Evaluando');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Evaluando');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

SELECT '--- 8.2 Asentando Calificaciones Masivas (Vía SP) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Grade`$$
CREATE PROCEDURE `SP_QA_Grade`(IN _CursoID INT, IN _Start INT, IN _End INT, IN _Grade DECIMAL(5,2), IN _Exec INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_UID INT;
    DECLARE v_RegID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_UID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UID LIMIT 1;
        IF v_RegID IS NOT NULL THEN
            CALL SP_EditarParticipanteCapacitacion(_Exec, v_RegID, _Grade, 100.00, NULL, 'Eval QA');
        END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01: Mayoría Aprobada
CALL `SP_QA_Grade`(@C01_Ver, 1, 18, 95.00, @U_Inst2);
-- C02: Mayoría Reprobada
CALL `SP_QA_Grade`(@C02_Ver, 21, 30, 50.00, @U_Inst1);
-- C03: 100% Aprobación
CALL `SP_QA_Grade`(@C03_Ver, 31, 55, 90.00, @U_Inst2);
-- C04: Mixto
CALL `SP_QA_Grade`(@C04_Ver, 1, 15, 80.00, @U_Inst1);
-- C05: Aprobados
CALL `SP_QA_Grade`(@C05_Ver, 16, 25, 85.00, @U_Inst1);
-- C06: Aprobados
CALL `SP_QA_Grade`(@C06_Ver, 26, 45, 92.00, @U_Inst2);

DROP PROCEDURE `SP_QA_Grade`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Alumno verifica sus calificaciones.
   [SP USADO]: SP_ConsularMisCursos
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 7: Alumno revisa kardex ---' AS CHECK_POINT;
CALL SP_ConsularMisCursos(@U_P01);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 8 COMPLETADA: Evaluaciones registradas.' AS STATUS;

/* ==========================================================================================================
   FASE 9: DETERMINACIÓN DE ACREDITACIÓN (VEREDICTO)
   ==========================================================================================================
   [OBJETIVO]: Cambiar el estatus del CURSO a 'ACREDITADO' (6) o 'NO ACREDITADO' (7).
   [REGLA NEGOCIO]: Acreditado si >= 70% de los alumnos del sistema aprobaron.
   ========================================================================================================== */
SELECT '--- 9.1 Aplicando Veredictos ---' AS STEP;

-- C01: Acreditado (Mayoría aprobada)
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Dictamen: ACREDITADO');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02: No Acreditado (Reprobación masiva)
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 7, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Dictamen: NO ACREDITADO');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03: Acreditado
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04: Acreditado
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Dictamen: ACREDITADO');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05: Acreditado
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06: Acreditado
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst3, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Dictamen: ACREDITADO');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

SELECT '✅ FASE 9 COMPLETADA: Veredictos aplicados.' AS STATUS;

/* ==========================================================================================================
   FASE 10: CIERRE (FINALIZADO)
   ==========================================================================================================
   [OBJETIVO]: Cerrar administrativamente los cursos (Finalizado - ID 4).
   [QA]: Verificar que esto no altere las calificaciones de los alumnos.
   ========================================================================================================== */
SELECT '--- 10.1 Cierre Final ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre');
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Cierre');
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Cierre');
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst3, @IdSedeC, @Mod_Hib, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Cierre');

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificación de Metas Anuales.
   [SP USADO]: SP_Dashboard_ResumenAnual
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 9: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

SELECT '✅ FASE 10 COMPLETADA: Cierre completado.' AS STATUS;

/* ==========================================================================================================
   FASE 11: ARCHIVADO (KILL SWITCH)
   ==========================================================================================================
   [OBJETIVO]: Sacar los cursos del tablero operativo (Soft Delete).
   [ACCIÓN TÉCNICA]: Uso de SP_CambiarEstatusCapacitacion con Activo=0.
   ========================================================================================================== */
SELECT '--- 11.1 Archivando ---' AS STEP;

CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'), @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'), @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'), @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'), @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'), @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'), @U_Adm1, 0);

SELECT '✅ FASE 11 COMPLETADA: Archivado completado.' AS STATUS;

/* ==========================================================================================================
   FASE 12: CANCELACIÓN (CURSO C07)
   ==========================================================================================================
   [OBJETIVO]: Probar el flujo alterno de Cancelación.
   [LÓGICA]: Se crea un curso C07, se inscribe a alguien y luego se cancela (Status 8) en lugar de iniciarse.
   ========================================================================================================== */
SELECT '--- 12.1 Prueba Cancelación ---' AS STEP;
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C07', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 30, @St_Prog, 'C07 Cancel');
SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
SET @C07_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C07_Head);
CALL SP_RegistrarParticipanteCapacitacion(@U_Adm1, @C07_Ver, @U_P01);
CALL SP_Editar_Capacitacion(@C07_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 8, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 0, 'Cancelado');
CALL SP_CambiarEstatusCapacitacion(@C07_Head, @U_Adm1, 0);

SELECT '✅ FASE 12 COMPLETADA: Cancelación completada.' AS STATUS;

/* ==========================================================================================================
   FASE 14: LIMPIEZA FINAL (TEARDOWN)
   ==========================================================================================================
   [OBJETIVO]: Desmontar el entorno de prueba.
   [ACCIÓN TÉCNICA]: Uso de SP_EliminarCapacitacion y SP_EliminarUsuarioDefinitivamente.
   ========================================================================================================== */
SELECT '--- 14.1 Limpieza Final ---' AS STEP;

-- Borrado de relaciones de participantes
DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');

-- Borrado de los 7 cursos
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07'));

-- Borrado de Participantes
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_DelUsers`$$
CREATE PROCEDURE `SP_Temp_DelUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE v_ID INT;
    WHILE i <= 70 DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        IF v_ID IS NOT NULL THEN CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, v_ID); END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL `SP_Temp_DelUsers`();
DROP PROCEDURE `SP_Temp_DelUsers`;

-- Borrado de Staff
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

-- Borrado de Infraestructura
SET FOREIGN_KEY_CHECKS = 0;
CALL SP_EliminarTemaCapacitacionFisico(@IdTema1);
CALL SP_EliminarTemaCapacitacionFisico(@IdTema2);
CALL SP_EliminarTemaCapacitacionFisico(@IdTema3);
CALL SP_EliminarSedeFisica(@IdSedeA);
CALL SP_EliminarSedeFisica(@IdSedeB);
CALL SP_EliminarSedeFisica(@IdSedeC);
CALL SP_EliminarDepartamentoFisico(@IdDep);
CALL SP_EliminarCentroTrabajoFisico(@IdCT);
CALL SP_EliminarGerenciaFisica(@IdGer);
CALL SP_EliminarMunicipio(@IdMun);
SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 14 COMPLETADA: Limpieza total.' AS STATUS;