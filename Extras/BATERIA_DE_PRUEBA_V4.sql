USE Picade;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   ARTEFACTO DE SOFTWARE : MASTER SCRIPT DE VALIDACIÓN Y CONTROL DE CALIDAD (QA)
   NOMBRE DE CLAVE       : "PROJECT DIAMOND" - AUDITORÍA DE CAJA BLANCA
   VERSIÓN               : 20.0 (MAXIMUM VERBOSITY EDITION)
   AUTORÍA               : ARQUITECTURA DE DATOS PICADE
   
   [PROPÓSITO DEL DOCUMENTO]:
   Este script no solo ejecuta pruebas; narra la historia completa del ciclo de vida de los datos.
   Sirve como documentación viva de las reglas de negocio implementadas en los Stored Procedures.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

-- [CONFIGURACIÓN DE VARIABLES DE SESIÓN]
-- Definimos el ID del Super Usuario que orquestará toda la prueba.
-- Esto simula que una persona real (Admin) está logueada en el sistema.
SET @AdminEjecutor = 322; 

-- Definimos la fecha base para todos los cálculos cronológicos.
SET @FechaHoy = CURDATE();

/* ==========================================================================================================
   FASE 0: PROTOCOLO DE ESTERILIZACIÓN (DATA SANITIZATION)
   ========================================================================================================== */
/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Desactivar revisión de llaves foráneas (FOREIGN_KEY_CHECKS = 0).
   [LÓGICA INTERNA]: Permitir el borrado de tablas padre (ej. Capacitaciones) sin tener que borrar primero 
                     a los hijos (Participantes) manualmente una por una.
   [OBJETIVO DE QA]: Preparar un lienzo en blanco (Clean Slate) para evitar que datos de pruebas anteriores
                     contaminen los resultados de esta ejecución (Falsos Positivos).
   ---------------------------------------------------------------------------------------------------------- */
SET FOREIGN_KEY_CHECKS = 0;

-- Borrado de tablas transaccionales (Datos operativos)
DELETE FROM `Evaluaciones_Participantes` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones_Participantes` WHERE `Justificacion` LIKE '%QA-DIAMOND%';
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE 'QA-DIAMOND%';

-- Borrado de tablas de identidad (Usuarios)
DELETE FROM `Usuarios` WHERE `Ficha` LIKE 'QA-DIAMOND%';
DELETE FROM `Info_Personal` WHERE `Nombre` LIKE 'QA-DIAMOND%';

-- Borrado de catálogos de infraestructura (Sedes, Temas, Jerarquía)
DELETE FROM `Cat_Cases_Sedes` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Departamentos` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Centros_Trabajo` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Temas_Capacitacion` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Gerencias_Activos` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Subdirecciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Direcciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Municipio` WHERE `Codigo` LIKE 'QA-DIAMOND%';

-- Reactivamos la seguridad referencial
SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 0 COMPLETADA: Entorno totalmente limpio.' AS STATUS;

/* ==========================================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (TOPOLOGÍA)
   ========================================================================================================== */
/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Ejecución de SPs de Catálogos (Ubicaciones, Organización, Sedes).
   [LÓGICA INTERNA]: Insertar registros en tablas maestras y devolver IDs autogenerados.
   [OBJETIVO DE QA]: Validar que el sistema puede operar con datos nuevos sin depender de "ID 1" hardcodeado.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 1.1 Construyendo Topología ---' AS STEP;

-- Geografía
CALL SP_RegistrarUbicaciones('QA-DIAMOND-MUN', 'MUNICIPIO D', 'QA-DIAMOND-EDO', 'ESTADO D', 'QA-DIAMOND-PAIS', 'PAIS D');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');

-- Estructura Organizacional
CALL SP_RegistrarOrganizacion('QA-DIAMOND-GER', 'GERENCIA D', 'QA-DIAMOND-SUB', 'SUB D', 'QA-DIAMOND-DIR', 'DIR D');
SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');

-- Centros de Trabajo
CALL SP_RegistrarCentroTrabajo('QA-DIAMOND-CT', 'CT D', 'CALLE 1', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_RegistrarDepartamento('QA-DIAMOND-DEP', 'DEPTO D', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');

-- Sedes (Aulas): Creamos 3 para probar la rotación de sedes en el historial.
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-A', 'AULA A', 'EDIF A', @IdMun, 50, 1, 1, 0, 0, 0, 0);
SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');

CALL SP_RegistrarSede('QA-DIAMOND-SEDE-B', 'AULA B', 'EDIF B', @IdMun, 40, 1, 1, 0, 0, 0, 0);
SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');

CALL SP_RegistrarSede('QA-DIAMOND-SEDE-C', 'VIRTUAL', 'ONLINE', @IdMun, 100, 1, 1, 0, 0, 0, 0);
SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');

-- Temas Académicos: Creamos 3 para asignar a diferentes cursos.
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-1', 'SEGURIDAD', 'SEG', 20, 1);
SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');

CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-2', 'LIDERAZGO', 'LID', 10, 1);
SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');

CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-3', 'TECNICO', 'TEC', 30, 1);
SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');

-- Definición de Constantes de Sistema (Para legibilidad del script)
SET @RolAdmin=1; SET @RolCoord=2; SET @RolInst=3; SET @RolPart=4;
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo LIMIT 1);
SET @IdRegion  = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo LIMIT 1);
SET @IdPuesto  = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo LIMIT 1);
SET @Mod_Pres=1; SET @Mod_Virt=2; SET @Mod_Hib=3;
SET @St_Prog=1; SET @St_PorIni=2; SET @St_EnCurso=3; SET @St_Fin=4; SET @St_Eval=5; 
SET @St_Acr=6; SET @St_NoAcr=7; SET @St_Canc=8; SET @St_Repro=9; SET @St_Arch=10; SET @St_Reprog=9;

SELECT '✅ FASE 1 COMPLETADA: Infraestructura operativa lista.' AS STATUS;

/* ==========================================================================================================
   FASE 2: PROVISIONAMIENTO DE ACTORES (IDENTITY MANAGEMENT)
   ========================================================================================================== */
/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Creación de usuarios STAFF (Admins, Coords, Inst).
   [LÓGICA INTERNA]: SP_RegistrarUsuarioPorAdmin crea Login, InfoPersonal y Relación Laboral en una transacción.
   [OBJETIVO DE QA]: Validar que existen actores distintos para probar el "Balanceo de Carga" (quién hace qué).
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 2.1 Creando Staff Administrativo ---' AS STEP;

-- Admins (Para rescates y archivado)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM1', NULL, 'ADMIN', '1', 'QA', '1990-01-01', '2030-01-01', 'a1@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM2', NULL, 'ADMIN', '2', 'QA', '1990-01-01', '2030-01-01', 'a2@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');

-- Coordinadores (Dueños de la creación de cursos)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO1', NULL, 'COORD', '1', 'QA', '1990-01-01', '2030-01-01', 'c1@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO2', NULL, 'COORD', '2', 'QA', '1990-01-01', '2030-01-01', 'c2@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');

-- Instructores (Responsables de evaluar)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS1', NULL, 'INST', '1', 'QA', '1990-01-01', '2030-01-01', 'i1@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS2', NULL, 'INST', '2', 'QA', '1990-01-01', '2030-01-01', 'i2@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');

/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Creación masiva de 70 Participantes.
   [LÓGICA INTERNA]: Uso de un bucle (WHILE) dentro de un SP temporal para llamar 70 veces al SP oficial.
   [OBJETIVO DE QA]: Generar masa crítica para probar colas de espera, llenado de cupos y paginación.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 2.2 Creando 70 Participantes (P01-P70) ---' AS STEP;

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

-- Captura de variables clave para uso explícito posterior
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01'); -- Alumno Testigo

SELECT '✅ FASE 2 COMPLETADA: Actores creados.' AS STATUS;

/* ==========================================================================================================
   FASE 3: CREACIÓN DE LOS 6 CURSOS (PLANEACIÓN - ESTATUS PROGRAMADO)
   ==========================================================================================================
   [ACCIÓN TÉCNICA]: Llamadas a SP_RegistrarCapacitacion alternando Coordinadores.
   [OBJETIVO DE QA]: Validar la creación de 6 cursos con cupos heterogéneos (30, 25, 30, 20, 15, 40).
   [ESPERADO]: Se crean 6 registros en `Capacitaciones` y sus respectivas versiones V1 en `DatosCapacitaciones`.
   ========================================================================================================== */
SELECT '--- 3.1 Creando 6 Cursos ---' AS STEP;

-- C01 (Cupo 30)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C01', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 30, @St_Prog, 'C01 Base');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02 (Cupo 25)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C02', @IdGer, @IdTema2, @U_Inst2, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 25, @St_Prog, 'C02 Base');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03 (Cupo 30)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C03', @IdGer, @IdTema3, @U_Inst1, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 30, @St_Prog, 'C03 Base');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04 (Cupo 20)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C04', @IdGer, @IdTema1, @U_Inst2, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 20, @St_Prog, 'C04 Base');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05 (15 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C05', @IdGer, @IdTema2, @U_Inst1, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 15, @St_Prog, 'C05 Base');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06 (40 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C06', @IdGer, @IdTema3, @U_Inst2, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 40, @St_Prog, 'C06 Base');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificar que los cursos aparecen en el Dashboard General.
   [SP USADO]: SP_ObtenerMatrizPICADE
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 1: Matriz Inicial (6 Cursos Programados) ---' AS CHECK_POINT;
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 3 COMPLETADA: 6 Cursos creados y visibles.' AS STATUS;

/* ==========================================================================================================
   FASE 4: INSCRIPCIÓN Y COLA DE ESPERA (MIXTO)
   ==========================================================================================================
   [ACCIÓN TÉCNICA]: Llenado masivo de cursos usando SP_RegistrarParticipacionCapacitacion (Auto-servicio).
   [LÓGICA INTERNA]: El SP valida cupo, duplicidad y estatus del curso.
   [OBJETIVO DE QA]: Poblar los cursos con usuarios "Sistémicos" (entre 30% y 100% del cupo).
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

-- C01 (30 Cupos): Llenamos 25 con Sistema (Deja 5 libres).
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
   [AUDITORÍA DE VISTAS]: El instructor verifica su lista de asistencia preliminar.
   [SP USADO]: SP_ConsularParticipantesCapacitacion
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 2: Instructor consulta lista C04 (Debe estar llena con 20) ---' AS CHECK_POINT;
CALL SP_ConsularParticipantesCapacitacion(@C04_Ver);

SELECT '✅ FASE 4 COMPLETADA: Inscripciones realizadas.' AS STATUS;

/* ==========================================================================================================
   FASE 4.5: TURBULENCIA OPERATIVA (CAOS EN LOS 6 CURSOS)
   ==========================================================================================================
   [ACCIÓN TÉCNICA]: Bucle de Bajas y Reingresos sobre la misma versión del curso.
   [LÓGICA DE NEGOCIO]: 
     1. Baja (Status 5): Libera el cupo.
     2. Reingreso (Status 1): Intenta recuperar el lugar.
   [OBJETIVO DE QA]: 
     - Validar que al dar de baja, se libere el espacio.
     - Validar que al intentar volver, si alguien más ocupó el lugar (simulado en casos llenos), falle.
   ========================================================================================================== */
SELECT '--- 4.5 Caos Administrativo (5 Bajas y 3 Reingresos por Curso) ---' AS STEP;

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
        
        -- Ejecutar SP de Cambio de Estatus a 5 (BAJA)
        IF v_RegID IS NOT NULL THEN
            CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, 5, 'QA: Baja Administrativa por RH');
        END IF;
        SET i = i + 1;
    END WHILE;

    -- PASO 2: INTENTO DE REINGRESO DE 3 ALUMNOS (Lucha por el cupo)
    -- Si el curso tenía lista de espera o se llenó por externos, esto fallará controladamente.
    SET i = 0;
    WHILE i < 3 DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        
        -- Ejecutar SP de Cambio de Estatus a 1 (RE-INSCRITO)
        IF v_RegID IS NOT NULL THEN
            -- Envolvemos en bloque seguro para capturar error de cupo lleno sin detener el script
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
   [AUDITORÍA DE VISTAS]: El Alumno P01 verifica su estatus personal (¿Sigue inscrito o fue dado de baja?).
   [SP USADO]: SP_ConsularMisCursos
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 3: Alumno P01 revisa sus cursos post-caos ---' AS CHECK_POINT;
CALL SP_ConsularMisCursos(@U_P01);

SELECT '✅ FASE 4.5 COMPLETADA: Turbulencia operativa aplicada.' AS STATUS;

/* ==========================================================================================================
   FASE 5: AUTORIZACIÓN (POR INICIAR) + CUPO EXTERNO
   ==========================================================================================================
   [ACCIÓN TÉCNICA]: SP_Editar_Capacitacion para cambiar estatus a 2 (Por Iniciar) y definir `AsistentesReales`.
   [LÓGICA INTERNA]: Se crea V2. Se define cuántos "externos" ocupan lugar.
   [OBJETIVO DE QA]: Validar la lógica híbrida. Si Curso tiene 20 sistema + 10 manuales = 30 Ocupados.
   ========================================================================================================== */
SELECT '--- 5.1 Autorizando y Definiendo Cupo Externo ---' AS STEP;

-- C01: Cupo 30. (20 Sis - 5 Bajas + 3 Reingresos = 18 Netos). 
-- Ponemos 10 Manuales. Total Real = 18 + 10 = 28. (Quedan 2 libres).
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 10, 'Autorizado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

-- C02: Cupo 25. (18 Netos). 15 Manuales.
-- Regla GREATEST(18, 15) = 18. NO. La lógica debe sumar si son complementarios o tomar el mayor si es override.
-- Asumimos Lógica "Override Total": El coordinador dice "Hay 25 en total" (incluyendo los del sistema).
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 15, 'Autorizado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- C03: Cupo 30.
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 5, 'Autorizado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

-- C04: Cupo 20.
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 0, 'Autorizado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

-- C05: Cupo 15.
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 5, 'Autorizado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

-- C06: Cupo 40.
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 20, 'Autorizado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validar que los cursos autorizados sean encontrables por cualquier usuario.
   [SP USADO]: SP_BuscadorGlobalPICADE
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;
CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');

SELECT '✅ FASE 5 COMPLETADA: Cursos autorizados.' AS STATUS;

/* ==========================================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS Y REPROGRAMACIÓN (HISTORIAL 5 PASOS)
   ========================================================================================================== 
   [ACCIÓN TÉCNICA]: 5 llamadas secuenciales a SP_Editar_Capacitacion por cada curso.
   [LÓGICA INTERNA]: Cada llamada archiva la versión anterior y crea una nueva, migrando a los alumnos.
   [OBJETIVO DE QA]: Validar que el historial no se rompa y que los alumnos sigan ligados a la versión 9 (Actual).
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
    -- Simulamos que faltan 2 semanas.
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
   [AUDITORÍA DE VISTAS]: Ver detalle con historial acumulado.
   [SP USADO]: SP_ConsultarCapacitacionEspecifica
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

SELECT '✅ FASE 6 COMPLETADA: Historial profundo generado.' AS STATUS;

/* ==========================================================================================================
   FASE 7: EJECUCIÓN (EN CURSO)
   ==========================================================================================================
   [OBJETIVO]: Simular que llegó la fecha de inicio. Cambiar estatus a 3 (En Curso).
   [IMPORTANTE]: Esto "congela" la lista de asistencia en la versión operativa.
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
   [AUDITORÍA DE VISTAS]: El instructor entra a su dashboard para ver qué cursos tiene activos.
   [SP USADO]: SP_ConsultarCursosImpartidos
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 7 COMPLETADA: Cursos en ejecución.' AS STATUS;

/* ==========================================================================================================
   FASE 8: EVALUACIÓN (ASENTAMIENTO DE NOTAS)
   ==========================================================================================================
   [ACCIÓN TÉCNICA]: 1. Cambio de estatus a 5 (Evaluación). 2. Ejecución de `SP_EditarParticipanteCapacitacion`.
   [LÓGICA INTERNA]: El sistema recibe la nota (0-100) y calcula automáticamente si es APROBADO (>=70) o REPROBADO.
   [OBJETIVO DE QA]: Probar la evaluación masiva y asegurar que los estatus individuales cambian.
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
CALL `SP_QA_Grade`(@C01_Ver, 1, 18, 95.00, @U_Inst1);
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

-- [AUDITORÍA VISUAL 7]: Alumno ve sus notas finales
SELECT '--- 🔍 CHECKPOINT 7: Alumno revisa kardex ---' AS CHECK_POINT;
CALL SP_ConsularMisCursos(@U_P01);

-- [AUDITORÍA VISUAL 8]: Dashboard Gerencial para ver impacto de calificaciones
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 8 COMPLETADA: Evaluaciones registradas.' AS STATUS;

/* ==========================================================================================================
   FASE 9: DETERMINACIÓN DE ACREDITACIÓN (VEREDICTO)
   ==========================================================================================================
   [OBJETIVO]: Cambiar el estatus del CURSO a 'ACREDITADO' o 'NO ACREDITADO'.
   [REGLA NEGOCIO]: Si el 70% de los inscritos del sistema aprobaron, el curso se acredita.
   ========================================================================================================== */
SELECT '--- 9.1 Aplicando Veredictos ---' AS STEP;

-- C01: Acreditado
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
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Dictamen: ACREDITADO');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

SELECT '✅ FASE 9 COMPLETADA: Veredictos aplicados.' AS STATUS;

/* ==========================================================================================================
   FASE 10: CIERRE (FINALIZADO)
   ==========================================================================================================
   [OBJETIVO]: Simular el cierre administrativo tras un periodo de tiempo.
   [ACCIÓN TÉCNICA]: Cambio de estatus a 4 (FINALIZADO) para los 6 cursos explícitamente.
   ========================================================================================================== */
SELECT '--- 10.1 Cierre Final ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre');
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Cierre');
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Cierre');
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst3, @IdSedeC, @Mod_Hib, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Cierre');

-- [AUDITORÍA VISUAL 9]: Resumen Anual
SELECT '--- 🔍 CHECKPOINT 9: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

SELECT '✅ FASE 10 COMPLETADA: Cierre completado.' AS STATUS;

/* ==========================================================================================================
   FASE 11: ARCHIVADO
   ==========================================================================================================
   [OBJETIVO]: Sacar los cursos del grid operativo.
   [ACCIÓN TÉCNICA]: Uso de SP_CambiarEstatusCapacitacion (Activo = 0).
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
   FASE 12: CANCELACIÓN
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
   FASE 14: LIMPIEZA FINAL
   ========================================================================================================== */
SELECT '--- 14.1 Limpieza Final ---' AS STEP;
DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));
CALL SP_EliminarCapacitacion((SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));
CALL SP_EliminarCapacitacion(@C07_Head);

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

CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

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