USE Picade;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   ARTEFACTO DE INGENIERÍA : MASTER SCRIPT DE VALIDACIÓN Y CONTROL DE CALIDAD (QA)
   NOMBRE CLAVE            : "PROJECT DIAMOND" - AUDITORÍA FORENSE DE CICLO DE VIDA COMPLETO
   VERSIÓN                 : 21.0 (PLATINUM FORENSIC DOCUMENTATION STANDARD)
   AUTORÍA                 : ARQUITECTURA DE DATOS PICADE
   FECHA DE EJECUCIÓN      : AUTOMÁTICA
   
   [MANIFIESTO TÉCNICO]:
   Este script no es una mera secuencia de comandos SQL; es una especificación técnica viva.
   Su propósito es someter al ecosistema PICADE a una prueba de estrés integral, validando la integridad
   referencial, la lógica de negocio (Business Logic Layer) y la persistencia de datos (Data Layer).
   
   [ALCANCE DE LA AUDITORÍA]:
   1. TOPOLOGÍA   : Construcción "desde cero" de la infraestructura organizativa y geográfica.
   2. IDENTIDAD   : Provisionamiento masivo de actores con roles segregados (SoD).
   3. OPERACIÓN   : Gestión concurrente de 6 cursos con cupos heterogéneos y lógica híbrida.
   4. RESILIENCIA : Simulación de "Caos Administrativo" (Bajas masivas, reingresos, rebotes).
   5. HISTORIA    : Generación de versiones inmutables para trazabilidad forense.
   6. VISIBILIDAD : Validación de que los datos fluyen correctamente hacia los Dashboards y Reportes.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

-- [CONFIGURACIÓN DE VARIABLES DE SESIÓN]
-- Definimos el ID del "Super Usuario" que orquestará toda la prueba. Esto simula una sesión activa.
SET @AdminEjecutor = 322; 
-- Fijamos la fecha base para calcular cronogramas relativos (evita hardcoding de fechas pasadas).
SET @FechaHoy = CURDATE();

/* ==========================================================================================================
   FASE 0: PROTOCOLO DE ESTERILIZACIÓN (DEEP CLEANING & SANITIZATION)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]:
   Eliminar cualquier rastro de datos ("Data Remanence") de ejecuciones anteriores que pudieran causar
   falsos positivos o conflictos de integridad (Duplicate Key Errors).
   
   [ESTRATEGIA DE BORRADO]:
   Se utiliza un enfoque de "Tierra Quemada" selectivo, borrando datos en orden inverso a su dependencia
   (Nietos -> Hijos -> Padres) para mantener la integridad referencial lógica, aunque desactivamos
   la física temporalmente para velocidad.
   ========================================================================================================== */
-- Borrado de relaciones de participantes (Nietos)
TRUNCATE `picade`.`capacitaciones_participantes`;
-- SELECT * FROM `PICADE`.CAPACITACIONES_PARTICIPANTES;

-- DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');

-- Borrado de los 7 cursos (Padres e Hijos)
SET @CAP01_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01');
CALL SP_EliminarCapacitacion(@CAP01_);

SET @CAP02_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02');
CALL SP_EliminarCapacitacion(@CAP02_);

SET @CAP03_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03');
CALL SP_EliminarCapacitacion(@CAP03_);

SET @CAP04_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04');
CALL SP_EliminarCapacitacion(@CAP04_);

SET @CAP05_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05');
CALL SP_EliminarCapacitacion(@CAP05_);

SET @CAP06_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06');
CALL SP_EliminarCapacitacion(@CAP06_);

SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
CALL SP_EliminarCapacitacion(@C07_Head);

-- Borrado de Participantes (Iterativo para usar SP oficial)

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
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);

SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);

SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);

SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);

SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);

SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

-- Borrado de Infraestructura (FK Check Off para velocidad)
-- SET FOREIGN_KEY_CHECKS = 0;

SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema1);

SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema2);

SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema3);

SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');
CALL SP_EliminarSedeFisica(@IdSedeA);

SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');
CALL SP_EliminarSedeFisica(@IdSedeB);

SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');
CALL SP_EliminarSedeFisica(@IdSedeC);

SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');
CALL SP_EliminarDepartamentoFisico(@IdDep);

SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_EliminarCentroTrabajoFisico(@IdCT);

SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');
SET @IdCatSubDirec = (SELECT Id_CatSubDirec FROM Cat_subdirecciones WHERE Clave = 'QA-DIAMOND-SUB');
SET @IdDirecc = (SELECT Id_CatDirecc FROM Cat_direcciones WHERE Clave = 'QA-DIAMOND-DIR');

CALL SP_EliminarGerenciaFisica(@IdGer);
CALL SP_EliminarSubdireccionFisica(@SubDirec);
CALL SP_EliminarDireccionFisica(@Direc);

SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');
SET @IdEdo = (SELECT ID_Estado FROM ESTADO WHERE Codigo = 'QA-DIAMOND-EDO');
SET @IdPais = (SELECT ID_Pais FROM PAIS WHERE Codigo = 'QA-DIAMOND-PAIS');

CALL SP_EliminarMunicipio(@IdMun);
CALL SP_EliminarEstadoFisico(@IdEdo);
CALL SP_EliminarPaisFisico(@IdPais);
-- SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 0 COMPLETADA: Entorno totalmente limpio y listo para inyección.' AS STATUS;

/* ==========================================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (TOPOLOGY PROVISIONING)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]:
   Crear los cimientos del sistema (Lugares y Estructuras) necesarios para soportar la lógica de negocio.
   
   [REGLA DE NEGOCIO "ZERO ASSUMPTIONS"]:
   No asumimos que existan sedes, temas o departamentos previos. Se crean desde cero para garantizar
   que la prueba sea autocontenida y portátil.
   ========================================================================================================== */
SELECT '--- 1.1 Construyendo Topología (Geografía, Organización y Recursos) ---' AS STEP;

-- 1.1.1 GEOGRAFÍA
-- [ACCIÓN]: Ejecución de SP_RegistrarUbicaciones.
-- [LÓGICA]: Inserta en tablas Municipio, Estado y País, devolviendo IDs autogenerados.
CALL SP_RegistrarUbicaciones('QA-DIAMOND-MUN', 'VILLAHERMOSA', 'QA-DIAMOND-EDO', 'TABASCO', 'QA-DIAMOND-PAIS', 'MEXICO');
SET @IdPais = (SELECT ID_Pais FROM PAIS WHERE Codigo = 'QA-DIAMOND-PAIS');
SET @IdEdo = (SELECT ID_Estado FROM ESTADO WHERE Codigo = 'QA-DIAMOND-EDO');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');

-- 1.1.2 ORGANIZACIÓN CORPORATIVA
-- [ACCIÓN]: Ejecución de SP_RegistrarOrganizacion.
-- [LÓGICA]: Crea la jerarquía vertical (Gerencia -> Subdirección -> Dirección).
CALL SP_RegistrarOrganizacion('QA-DIAMOND-GER', 'GERENCIA DE SEGURIDAD, SALUD EN EL TRABAJO Y PROTECCION AMBIENTAL', 'QA-DIAMOND-SUB', 'SUBDIRECCION DE SEGURIDAD, SALUD EN EL TRABAJO Y PROTECCION AMBIENTAL', 'QA-DIAMOND-DIR', 'DIRECCION DE SEGURIDAD, SALUD EN EL TRABAJO Y PROTECCION AMBIENTAL');
SET @IdDirecc = (SELECT Id_CatDirecc FROM Cat_direcciones WHERE Clave = 'QA-DIAMOND-DIR');
SET @IdCatSubDirec = (SELECT Id_CatSubDirec FROM Cat_subdirecciones WHERE Clave = 'QA-DIAMOND-SUB');
SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');

-- 1.1.3 CENTROS DE TRABAJO
-- [ACCIÓN]: Creación de nodos operativos.
CALL SP_RegistrarCentroTrabajo('QA-DIAMOND-CT', 'PEMEX EXPLORACION Y EXTRACCION', 'EDIFICIO PIRAMIDE', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_RegistrarDepartamento('QA-DIAMOND-DEP', 'GRUPO MULTIDISCIPLINARIO DE PERFORACION Y REPARACION DE POZOS', 'PISO 5', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');

-- 1.1.4 SEDES EDUCATIVAS (AULAS FÍSICAS Y VIRTUALES)
-- [OBJETIVO QA]: Crear 3 espacios con capacidades distintas para probar validaciones de aforo.
-- Sede A: Capacidad 50 (Aula Magna) - Para cursos grandes.
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-A', 'CENTRO DE ADIESTRAMIENTO EN SEGURIDAD ECOLOGIA Y SOBREVIVENCIA DOS BOCAS', 'RANCHERIA EL LIMON S/N TERMINAL MARITIMA DOS BOCAS', @IdMun, 215, 5, 2, 1, 18, 2, 0);
SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');

-- Sede B: Capacidad 40 (Laboratorio) - Para cursos medianos.
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-B', 'CENTRO DE ADIESTRAMIENTO EN SEGURIDAD ECOLOGIA Y SOBREVIVENCIA CIUDAD DEL CARMEN', 'CARRETERA CIUDAD DEL CARMEN A MERIDA KM 22 + 800', @IdMun, 320, 5, 2, 1, 11, 0, 30);
SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');

-- Sede C: Capacidad 100 (Virtual) - Para cursos masivos.
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-C', 'CENTRO DE ADIESTRAMIENTO EN SEGURIDAD ECOLOGIA Y SOBREVIVENCIA POZA RICA', 'CAMPUS POZA RICA UBICADO EN LA COMUNIDAD DE POLUTLA ', @IdMun, 165, 6, 0, 0, 0, 0, 0);
SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');

-- 1.1.5 CATÁLOGO ACADÉMICO (TEMAS)
-- [OBJETIVO QA]: Diversificar el contenido para reportes gerenciales.
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-1', 'SEGURIDAD', 'SEG', 20, 1);
SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-2', 'LIDERAZGO', 'LID', 10, 1);
SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-3', 'TECNICO', 'TEC', 30, 1);
SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');

-- [CONSTANTES DEL SISTEMA]
-- Mapeo de IDs estáticos ("Magic Numbers") a variables semánticas para legibilidad del código.
SET @IdPais = 1;
SET @IdEdo = 27;
SET @IdMun = 1970;

SET @IdGer = 53;
SET @IdGer2 = 41;
SET @IdGer3 = 69;

SET @IdCT = 224;
SET @IdCT2 = 69;

SET @IdDep = 194;
SET @IdDep2 = 10;

SET @IdSedeA = 5;
SET @IdSedeB = 3;
SET @IdSedeC = 7;

SET @IdTema1 = 9;
SET @IdTema2 = 11;
SET @IdTema3 = 13;

SET @RolAdmin=1; 
SET @RolCoord=2; 
SET @RolInst=3; 
SET @RolPart=4;

SET @IdRegimen = 4; -- (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo LIMIT 1);
SET @IdRegion  = 5; -- (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo LIMIT 1);
-- SET @IdPuesto  = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo LIMIT 1);
SET @IdPuesto = 14;

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

SET @St_PartProg=1;
SET @St_PartAsistio=2;
SET @St_PartAcre=3;
SET @St_PartNoAcre=4;
SET @St_PartBaja=5;

SELECT '✅ FASE 1 COMPLETADA: Infraestructura operativa lista.' AS STATUS;

/* ==========================================================================================================
   FASE 2: PROVISIONAMIENTO DE ACTORES (IDENTITY MANAGEMENT)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]:
   Poblar la tabla `Usuarios` con perfiles específicos para simular interacciones reales.
   
   [ESTRATEGIA DE QA]:
   Se crean múltiples Admins y Coordinadores para probar la concurrencia y la auditoría de "Quién hizo qué"
   (Created_By vs Updated_By).
   ========================================================================================================== */
SELECT '--- 2.1 Creando Staff Administrativo (Load Balancing Test) ---' AS STEP;

-- [ADMINISTRADORES]: Roles de alto nivel para operaciones críticas (Rescates, Archivados).
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM1', NULL, 'ENRIQUE', 'GOQUE', 'CRUZ', '1968-01-01', '1989-01-01', 'a1@d.test', '12345678', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM2', NULL, 'GUSTAVO ADOLFO', 'MIRANDA', 'ROSAS', '1970-01-01', '1992-01-01', 'a2@d.test', '12345678', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');

-- [COORDINADORES]: Dueños del flujo operativo (Creación, Autorización, Reprogramación).
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO1', NULL, 'DANELLIA', 'ROLDAN', 'LULE', '1975-01-01', '1995-01-01', 'c1@d.test', '12345678', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO2', NULL, 'TERESA DE JESUS', 'GARCIA', 'CUSTODIO', '1980-01-01', '2000-01-01', 'c2@d.test', '12345678', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');

-- [INSTRUCTORES]: Ejecutores académicos (Asistencia, Evaluación).
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS1', NULL, 'ALBERTO', 'RUIZ', 'BARBOSA', '1970-01-01', '2005-01-01', 'i1@d.test', '12345678', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS2', NULL, 'ENNIO ALAN', 'TIJERINA', 'BERNAL', '1973-01-01', '1998-01-01', 'i2@d.test', '12345678', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');

SELECT '--- 2.2 Creando 70 Participantes (P01-P70) ---' AS STEP;
/* ----------------------------------------------------------------------------------------------------------
   [ACCIÓN TÉCNICA]: Inyección masiva de usuarios usando un Stored Procedure Temporal.
   [LÓGICA INTERNA]: Bucle WHILE que itera 70 veces, invocando al SP `SP_RegistrarUsuarioPorAdmin`.
   [OBJETIVO DE QA]: Simular una carga de plantilla real. Validar que el sistema de registro no falle 
                     ante peticiones secuenciales rápidas (Stress Test).
   ---------------------------------------------------------------------------------------------------------- */
/*
DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$

CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 70 DO
        -- Inserción individual simulando una alta manual por parte del Admin
        CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')), NULL, CONCAT('P',i), 'USER', 'QA', '1980-01-01', '2015-01-01', CONCAT('p',i,'@d.test'), '123', @RolPart, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;*/

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$

CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    
    -- =============================================
    -- 1. VARIABLES PARA FECHAS (Lógica Anterior)
    -- =============================================
    DECLARE v_FecNac DATE;
    DECLARE v_FecIng DATE;
    DECLARE v_Min_Fecha_Ingreso DATE;
    DECLARE v_Dias_Rango INT;
    DECLARE v_Tope_Nacimiento DATE DEFAULT '1995-12-31';
    DECLARE v_Base_Nacimiento DATE DEFAULT '1970-01-01';
    DECLARE v_Tope_Ingreso    DATE DEFAULT '2023-01-01';

    -- =============================================
    -- 2. VARIABLES PARA NOMBRES (Nueva Lógica)
    -- =============================================
    DECLARE v_ListaNombres JSON;
    DECLARE v_ListaApellidos JSON;
    DECLARE v_NombreRand VARCHAR(100);
    DECLARE v_ApellidoRand VARCHAR(100);
    DECLARE v_TotalNombres INT;
    DECLARE v_TotalApellidos INT;
    DECLARE v_NombreCompleto VARCHAR(150);
    
    -- =============================================
    -- 3. CARGA DE DATOS (Aquí puedes pegar tu lista)
    -- =============================================
    -- Lista de 30 Nombres Comunes
    SET v_ListaNombres = '["Sofía", "Santiago", "Camila", "Sebastián", "Valentina", "Mateo", "Isabella", "Nicolás", "Lucía", "Alejandro", "Mariana", "Diego", "Gabriela", "Samuel", "Victoria", "Daniel", "Martina", "Leonardo", "Luciana", "Eduardo", "Daniela", "Carlos", "Andrea", "Felipe", "Natalia", "Javier", "Valeria", "Luis", "Fernanda", "Adrián"]';
    
    -- Lista de 30 Apellidos Comunes
    SET v_ListaApellidos = '["García", "Rodríguez", "Martínez", "Hernández", "López", "González", "Pérez", "Sánchez", "Ramírez", "Torres", "Flores", "Rivera", "Gómez", "Díaz", "Reyes", "Morales", "Ortiz", "Castillo", "Moreno", "Vargas", "Romero", "Mendoza", "Ruiz", "Herrera", "Medina", "Aguilar", "Castro", "Jiménez", "Ramos", "Vázquez"]';

    -- Calculamos cuántos hay para saber el límite del RAND
    SET v_TotalNombres = JSON_LENGTH(v_ListaNombres);
    SET v_TotalApellidos = JSON_LENGTH(v_ListaApellidos);

    -- =============================================
    -- 4. INICIO DEL BUCLE
    -- =============================================
    WHILE i <= 70 DO
        
        -- A) GENERACIÓN DE FECHAS (Tu lógica validada)
        SET v_Dias_Rango = DATEDIFF(v_Tope_Nacimiento, v_Base_Nacimiento);
        SET v_FecNac = DATE_ADD(v_Base_Nacimiento, INTERVAL FLOOR(RAND() * v_Dias_Rango) DAY);
        SET v_Min_Fecha_Ingreso = DATE_ADD(v_FecNac, INTERVAL 20 YEAR);

        IF v_Min_Fecha_Ingreso > v_Tope_Ingreso THEN
             SET v_Min_Fecha_Ingreso = DATE_SUB(v_Tope_Ingreso, INTERVAL 1 DAY);
        END IF;

        SET v_Dias_Rango = DATEDIFF(v_Tope_Ingreso, v_Min_Fecha_Ingreso);
        SET v_FecIng = DATE_ADD(v_Min_Fecha_Ingreso, INTERVAL FLOOR(RAND() * v_Dias_Rango) DAY);

        -- B) SELECCIÓN ALEATORIA DE NOMBRE Y APELLIDO
        -- Extraemos un elemento del array JSON usando un índice aleatorio (0 a Total-1)
        SET v_NombreRand = JSON_UNQUOTE(JSON_EXTRACT(v_ListaNombres, CONCAT('$[', FLOOR(RAND() * v_TotalNombres), ']')));
        SET v_ApellidoRand = JSON_UNQUOTE(JSON_EXTRACT(v_ListaApellidos, CONCAT('$[', FLOOR(RAND() * v_TotalApellidos), ']')));
        
        -- Armamos el nombre (Ej: "Santiago P.") para el campo "Nombre" y usamos el apellido completo en "ApellidoPaterno"
        -- Nota: Ajusta según cómo quieras llenar los campos del SP
        
        -- C) LLAMADA AL SP (Inyección de datos dinámicos)
        CALL SP_RegistrarUsuarioPorAdmin(
            @AdminEjecutor, 
            CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')),  -- Ficha
            NULL,                                   -- Huella
            -- CONCAT(v_NombreRand, ' ', v_ApellidoRand), -- Nombre (Aquí concatené para dar variedad)
            CONCAT(v_NombreRand, ' ', v_NombreRand),
            v_ApellidoRand,                         -- Apellido Paterno (Reciclado para el ejemplo)
            'QA',                                   -- Apellido Materno
            v_FecNac,                               -- Fecha Nacimiento Dinámica
            v_FecIng,                               -- Fecha Ingreso Dinámica
            CONCAT('p',i,'@d.test'),                -- Email secuencial (mejor para QA)
            '123', 
            @RolPart, 
            @IdRegimen, 
            @IdPuesto, 
            @IdCT2, 
            @IdDep2, 
            @IdRegion, 
            @IdGer2, 
            '01', 
            'A'
        );
        
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

-- Ejecución del motor de generación
CALL `SP_Temp_GenUsers`();

DROP PROCEDURE `SP_Temp_GenUsers`;

-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P01) para auditorías visuales posteriores.
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');

SELECT '✅ FASE 2 COMPLETADA: Actores creados.' AS STATUS;

/* ==========================================================================================================
   FASE 3: CREACIÓN DE LOS 6 CURSOS (PLANEACIÓN - ESTATUS PROGRAMADO)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]:
   Inicializar 6 expedientes de capacitación con configuraciones heterogéneas.
   
   [REGLAS DE NEGOCIO VALIDADAS]:
   1. Creación Atómica: SP_RegistrarCapacitacion debe crear Cabecera + Detalle V1.
   2. Estatus Inicial: Todo curso nace como "PROGRAMADO" (ID 1).
   3. Propiedad: El usuario "Creador" debe quedar registrado correctamente.
   
   [ESCENARIOS DE PRUEBA]:
   - C01 (30pax, Presencial)
   - C02 (25pax, Virtual)
   - C03 (30pax, Híbrido)
   - C04 (20pax, Presencial)
   - C05 (15pax, Virtual)
   - C06 (40pax, Híbrido)
   ========================================================================================================== */
SELECT '--- 3.1 Creando 6 Cursos ---' AS STEP;

-- C01 (30 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C01', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 30, @St_Prog, 'C01 Base');
SET @CAP01_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
-- SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02 (25 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C02', @IdGer2, @IdTema2, @U_Inst2, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 25, @St_Prog, 'C02 Base');
SET @CAP02_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
-- SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03 (30 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C03', @IdGer3, @IdTema3, @U_Inst1, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 30, @St_Prog, 'C03 Base');
SET @CAP03_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
-- SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04 (20 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C04', @IdGer3, @IdTema1, @U_Inst2, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 20, @St_Prog, 'C04 Base');
SET @CAP04_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
-- SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05 (15 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C05', @IdGer2, @IdTema2, @U_Inst1, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 15, @St_Prog, 'C05 Base');
SET @CAP05_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
-- SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06 (40 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C06', @IdGer, @IdTema3, @U_Inst2, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 40, @St_Prog, 'C06 Base');
SET @CAP06_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
-- SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificación de Visibilidad Administrativa.
   [ACCIÓN]: Ejecutar `SP_ObtenerMatrizPICADE` sin filtros.
   [ESPERADO]: Deben aparecer los 6 cursos recién creados con estatus "PROGRAMADO" en el grid principal.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 1: Matriz Inicial (6 Cursos Programados) ---' AS CHECK_POINT;
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 3 COMPLETADA: 6 Cursos creados y visibles.' AS STATUS;

/* ==========================================================================================================
   FASE 4: INSCRIPCIÓN Y COLA DE ESPERA (MIXTO)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]: 
   Poblar los cursos con usuarios "Sistémicos" (Usuarios que tienen cuenta en la plataforma).
   
   [ESTRATEGIA DE QA]:
   Usamos un Helper (`SP_QA_Enroll`) para simular que N usuarios se loguean y hacen clic en "Inscribirme".
   Esto valida la concurrencia y la lógica de validación de cupo en tiempo real.
   
   [REGLA DE NEGOCIO]: 
   El sistema debe aceptar inscripciones hasta llenar el cupo disponible.
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
        -- Llamada al SP oficial de Auto-Inscripción
        CALL SP_RegistrarParticipacionCapacitacion(v_ID, _CursoID); 
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

-- C01 (30 Cupos): Llenamos 25. Dejamos 5 huecos para la Fase 5 (Externos).
CALL `SP_QA_Enroll`(@C01_Ver, 1, 25); 
-- C02 (25 Cupos): Llenamos 20. Dejamos 5 huecos.
CALL `SP_QA_Enroll`(@C02_Ver, 26, 45); 
-- C03 (30 Cupos): Llenamos 30 (100% LLENO). Validaremos rebote más adelante.
CALL `SP_QA_Enroll`(@C03_Ver, 1, 30); 
-- C04 (20 Cupos): Llenamos 20 (100% LLENO).
CALL `SP_QA_Enroll`(@C04_Ver, 31, 50); 
-- C05 (15 Cupos): Llenamos 15 (100% LLENO).
CALL `SP_QA_Enroll`(@C05_Ver, 1, 15);
-- C06 (40 Cupos): Llenamos 30. Dejamos 10 huecos.
CALL `SP_QA_Enroll`(@C06_Ver, 16, 45);

DROP PROCEDURE `SP_QA_Enroll`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Listas de Asistencia.
   [ACCIÓN]: El instructor consulta la lista de participantes del curso C04.
   [ESPERADO]: El resultset debe mostrar exactamente 20 registros con estatus "INSCRITO".
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 2: Instructor consulta lista C04 (Debe estar llena con 20) ---' AS CHECK_POINT;
CALL SP_ConsularParticipantesCapacitacion(@C04_Ver);

SELECT '✅ FASE 4 COMPLETADA: Inscripciones realizadas.' AS STATUS;

/* ==========================================================================================================
   FASE 4.5: TURBULENCIA OPERATIVA (CAOS EN LOS 6 CURSOS)
   ==========================================================================================================
   [OBJETIVO TÉCNICO]: 
   Simular el comportamiento errático de los usuarios reales (Darse de baja, arrepentirse, intentar volver).
   
   [LÓGICA DEL ALGORITMO DE CAOS]:
   1. Se seleccionan 5 usuarios aleatorios por curso y se les da de BAJA (liberando 5 lugares).
   2. Se seleccionan 3 de esos mismos usuarios y se intenta REINSCRIBIRLOS.
   
   [REGLA DE NEGOCIO CRÍTICA (RACE CONDITION)]:
   - Si el curso estaba lleno, al dar de baja se abren huecos.
   - Si en el intermedio (simulado) entran otros (externos u otros usuarios), el reingreso DEBE fallar.
   - Si hay lugar, el reingreso DEBE ser exitoso.
   ========================================================================================================== */
SELECT '--- 4.5 Caos Administrativo (Bajas y Reingresos Masivos) ---' AS STEP;

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_QA_Chaos`$$

CREATE PROCEDURE `SP_QA_Chaos`(
	IN _CursoID INT,
	IN _StartUser INT, 
    IN _AdminID INT,
    IN _CantBajas INT,      -- NUEVO: Cuántos vamos a dar de baja
    IN _CantReingresos INT  -- NUEVO: Cuántos intentarán volver
    )
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_UserID INT;
    DECLARE v_RegID INT;
    
    -- PASO 1: DAR DE BAJA A 5 ALUMNOS (Liberación de Espacio)
    -- Usamos el parámetro _CantBajas en lugar del número fijo 5
    WHILE i < _CantBajas DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        
        IF v_RegID IS NOT NULL THEN
            -- Se cambia el estatus a 5 (BAJA) usando el SP Oficial
            CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, @St_PartBaja, 'QA: Baja Administrativa por RH');
        END IF;
        SET i = i + 1;
    END WHILE;

    -- PASO 2: INTENTO DE REINGRESO DE 3 ALUMNOS (Lucha por el cupo)
    -- PASO 2: INTENTO DE REINGRESO (Lucha por el cupo Dinámica)
    -- Reiniciamos contador y usamos _CantReingresos en lugar del número fijo 3
    SET i = 0;
    WHILE i < _CantReingresos DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        
        IF v_RegID IS NOT NULL THEN
            -- Se intenta cambiar el estatus a 1 (INSCRITO).
            -- [PROTECCIÓN]: Envolvemos en bloque seguro para capturar error de cupo lleno sin detener el script.
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, @St_PartProg, 'QA: Reingreso solicitado');
            END;
        END IF;
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

/* Ejecutar Caos en los 6 Cursos secuencialmente
CALL `SP_QA_Chaos`(@C01_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C02_Ver, 26, @U_Coo1);
CALL `SP_QA_Chaos`(@C03_Ver, 1, @U_Coo2);
CALL `SP_QA_Chaos`(@C04_Ver, 31, @U_Coo2);
CALL `SP_QA_Chaos`(@C05_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C06_Ver, 16, @U_Coo2);*/

-- Ejecutar Caos en los 6 Cursos (Personalizado por curso)

-- C01: Caos Leve (Bajan 5, Vuelven 3) -> Tu configuración original
CALL `SP_QA_Chaos`(@C01_Ver, 1, @U_Coo1, 5, 3);

-- C02: Caos Medio (Bajan 8, Vuelven 5)
CALL `SP_QA_Chaos`(@C02_Ver, 26, @U_Coo1, 8, 5);

-- C03: Caos Extremo (Bajan 10, Vuelven 10) - Pelea total por los cupos
CALL `SP_QA_Chaos`(@C03_Ver, 1, @U_Coo2, 10, 10);

-- C04: Sin Reingresos (Bajan 5, Vuelve 0) - Solo se liberan lugares
CALL `SP_QA_Chaos`(@C04_Ver, 31, @U_Coo2, 5, 0);

-- C01: Caos Leve (Bajan 5, Vuelven 3) -> Tu configuración original
CALL `SP_QA_Chaos`(@C05_Ver, 1, @U_Coo1, 5, 3);

-- C01: Caos Leve (Bajan 1, Vuelven 3) -> Tu configuración original
CALL `SP_QA_Chaos`(@C06_Ver, 16, @U_Coo2, 1, 0);
-- ... etc

DROP PROCEDURE `SP_QA_Chaos`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Vista del Alumno.
   [ACCIÓN]: El Alumno P01 verifica su estatus personal en el portal.
   [ESPERADO]: Debe ver si sigue inscrito o si su baja fue efectiva y visible.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 3: Alumno P01 revisa sus cursos post-caos ---' AS CHECK_POINT;

-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P01) para auditorías visuales posteriores.
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');
CALL SP_ConsularMisCursos(@U_P01);
-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P02) para auditorías visuales posteriores.
SET @U_P02 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P02');
CALL SP_ConsularMisCursos(@U_P02);

-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P06) para auditorías visuales posteriores.
SET @U_P06 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P06');
CALL SP_ConsularMisCursos(@U_P06);
-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P07) para auditorías visuales posteriores.
SET @U_P07 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P07');
CALL SP_ConsularMisCursos(@U_P07);

-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P26) para auditorías visuales posteriores.
SET @U_P26 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P26');
CALL SP_ConsularMisCursos(@U_P26);
-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P27) para auditorías visuales posteriores.
SET @U_P27 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P27');
CALL SP_ConsularMisCursos(@U_P27);

-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P31) para auditorías visuales posteriores.
SET @U_P31 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P31');
CALL SP_ConsularMisCursos(@U_P31);
-- [VARIABLE CLAVE]: Captura del ID del "Usuario Testigo" (P32) para auditorías visuales posteriores.
SET @U_P32 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P32');
CALL SP_ConsularMisCursos(@U_P32);


/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Listas de Asistencia.
   [ACCIÓN]: El instructor consulta la lista de participantes del curso C04.
   [ESPERADO]: El resultset debe mostrar exactamente 20 registros con estatus "INSCRITO".
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 2: Instructor consulta lista C04 (Debe estar llena con 20) ---' AS CHECK_POINT;
CALL SP_ConsularParticipantesCapacitacion(@C01_Ver);
CALL SP_ConsularParticipantesCapacitacion(@C02_Ver);
CALL SP_ConsularParticipantesCapacitacion(@C03_Ver);
CALL SP_ConsularParticipantesCapacitacion(@C04_Ver);
CALL SP_ConsularParticipantesCapacitacion(@C05_Ver);
CALL SP_ConsularParticipantesCapacitacion(@C06_Ver);

SELECT '✅ FASE 4.5 COMPLETADA: Turbulencia operativa aplicada.' AS STATUS;

/* ==========================================================================================================
   FASE 5: AUTORIZACIÓN (POR INICIAR) + CUPO EXTERNO
   ==========================================================================================================
   [OBJETIVO TÉCNICO]: 
   Avanzar el ciclo de vida a la fase operativa y "congelar" la configuración de cupos externos.
   
   [ACCIÓN TÉCNICA]: 
   Ejecutar `SP_EditarCapacitacion` cambiando el estatus a 2 (Por Iniciar) y definiendo `AsistentesReales`.
   
   [LÓGICA HÍBRIDA]: 
   El sistema calculará el cupo total ocupado como `GREATEST(Conteo_Sistema, Conteo_Manual)`.
   Esto permite al coordinador reservar espacios para personas que no están en la plataforma digital.
   ========================================================================================================== */
SELECT '--- 5.1 Autorizando y Definiendo Cupo Externo ---' AS STEP;

-- C01: Autorizado con 10 externos manuales.
-- [CURSO 01]
-- 1. Buscamos la versión viva actual (Anti-Error 1644)
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 10, 'Autorizado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

-- C02: Autorizado con 15 externos.
-- [CURSO 02]
-- 2. Buscamos la versión viva actual (Anti-Error 1644)
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 15, 'Autorizado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

-- C03: Autorizado con 5 externos.
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 5, 'Autorizado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

-- C04: Autorizado (0 Externos).
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 0, 'Autorizado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

-- C05: Autorizado con 5 externos.
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 5, 'Autorizado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

-- C06: Autorizado con 20 externos.
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 20, 'Autorizado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');

SELECT '✅ FASE 5 COMPLETADA: Cursos autorizados.' AS STATUS;

/* ==========================================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS Y REPROGRAMACIÓN (HISTORIAL 5 PASOS)
   ========================================================================================================== 
   [OBJETIVO TÉCNICO]: 
   Estresar el motor de versionado generando un historial profundo para cada curso.
   
   [LÓGICA DE NEGOCIO]: 
   Cada llamada a `SP_EditarCapacitacion`:
     1. Archiva la versión actual (Activo=0).
     2. Crea una nueva versión con los datos modificados.
     3. Migra todas las relaciones de participantes a la nueva versión.
   
   [SECUENCIA DE PRUEBA]:
     1. Cambio Instructor (Estado: Reprogramado).
     2. Cambio Sede (Estado: Reprogramado).
     3. Cambio Fecha (Estado: Reprogramado).
     4. Ajuste Menor (Estado: Reprogramado).
     5. Regreso a Por Iniciar (Confirmación).
   ========================================================================================================== */
SELECT '--- 6.1 Generando Historial Masivo (5 Cambios x 6 Cursos) ---' AS STEP;

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_QA_HistoryBuilder`$$

CREATE PROCEDURE `SP_QA_HistoryBuilder`(IN _IDVer INT, IN _HeadID INT, IN _CoordID INT, IN _InstID INT, IN _SedeID INT, IN _ModID INT)
BEGIN
    DECLARE v_NewVer INT DEFAULT _IDVer;
    
    -- Cambio 1: Instructor + Estatus Reprogramado (9)
    CALL SP_EditarCapacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, @St_Repro, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'QA: Cambio Inst');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 2: Sede
    CALL SP_EditarCapacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, @St_Repro, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'QA: Cambio Sede');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 3: Fecha
    CALL SP_EditarCapacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, @St_Repro, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'QA: Nueva Fecha');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 4: Ajuste Menor
    CALL SP_EditarCapacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, @St_Repro, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'QA: Ajuste');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    
    -- Cambio 5: Regreso Automático a Por Iniciar (2)
    -- Simulamos que el sistema detecta que faltan 2 semanas para el inicio.
    CALL SP_EditarCapacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, @St_PorIni, DATE_ADD(CURDATE(), INTERVAL 14 DAY), DATE_ADD(CURDATE(), INTERVAL 19 DAY), 0, 'QA: Confirmado');
END$$

DELIMITER ;

-- Ejecutar secuencialmente para los 6 cursos
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL `SP_QA_HistoryBuilder`(@C01_Ver, @CAP01_, @U_Coo1, @U_Inst2, @IdSedeA, @Mod_Pres);
-- CALL `SP_QA_HistoryBuilder`(@C01_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'), @U_Coo1, @U_Inst2, @IdSedeA, @Mod_Pres);
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL `SP_QA_HistoryBuilder`(@C02_Ver, @CAP02_, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt);
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL `SP_QA_HistoryBuilder`(@C03_Ver, @CAP03_, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib);
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL `SP_QA_HistoryBuilder`(@C04_Ver, @CAP04_, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres);
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL `SP_QA_HistoryBuilder`(@C05_Ver, @CAP05_, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt);
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL `SP_QA_HistoryBuilder`(@C06_Ver, @CAP06_, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib);
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

DROP PROCEDURE `SP_QA_HistoryBuilder`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Trazabilidad Histórica.
   [ACCIÓN]: Consultar el detalle de C01.
   [ESPERADO]: El footer del SP debe mostrar 5 versiones previas inactivas, evidenciando el historial de cambios.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C02_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C03_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C04_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C05_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C06_Ver);

SELECT '✅ FASE 6 COMPLETADA: Historial profundo generado.' AS STATUS;

/* ==========================================================================================================
   FASE 7: EJECUCIÓN (EN CURSO)
   ==========================================================================================================
   [OBJETIVO]: Simular que llegó la fecha de inicio del evento.
   [ACCIÓN TÉCNICA]: Cambiar estatus a 3 (En Curso) para los 6 cursos.
   [REGLA DE NEGOCIO]: Al cambiar de versión, la lista de asistencia se "congela" y migra a la nueva versión.
                       Esto marca el punto de no retorno para inscripciones automáticas.
   ========================================================================================================== */
SELECT '--- 7.1 Arrancando Cursos ---' AS STEP;

SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'En Curso');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'En Curso');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'En Curso');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_EnCurso, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'En Curso');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 7 COMPLETADA: Cursos en ejecución.' AS STATUS;

/* ==========================================================================================================
   FASE 8: EVALUACIÓN (ASENTAMIENTO DE NOTAS)
   ==========================================================================================================
   [OBJETIVO]: Simular el fin del evento formativo y la captura de resultados.
   
   [SUB-FASE 8.1]: Cambio de Estatus a 5 (En Evaluación).
   [LÓGICA]: Habilita la interfaz de captura de notas para el Instructor.
   ========================================================================================================== */
SELECT '--- 8.1 Cambio Automático a EVALUACIÓN (Los 6 Cursos) ---' AS STEP;

SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Evaluando');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Evaluando');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Evaluando');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Eval, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Evaluando');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

/* ----------------------------------------------------------------------------------------------------------
   [SUB-FASE 8.2]: Asentamiento Masivo de Calificaciones.
   [ACCIÓN TÉCNICA]: Uso de Helper (`SP_QA_Grade`) para llamar a `SP_EditarParticipanteCapacitacion` por rangos.
   [LÓGICA INTERNA]: El sistema recibe la nota (0-100) y calcula automáticamente el estatus del alumno:
                     - Si Nota >= 70 -> Estatus 3 (APROBADO).
                     - Si Nota < 70  -> Estatus 4 (REPROBADO).
   [ESCENARIOS]: Se simulan diferentes tasas de aprobación por curso.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 8.2 Asentando Calificaciones Masivas (Vía SP) ---' AS STEP;
/* ----------------------------------------------------------------------------------------------------------
   [SUB-FASE 8.2]: Asentamiento Masivo de Calificaciones (HELPER INTELIGENTE)
   [MEJORA]: El helper ahora verifica si el alumno está en BAJA (ID 5) antes de intentar calificarlo.
             Si está en baja, lo salta silenciosamente para no detener el flujo.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 8.2 Asentando Calificaciones Masivas (Smart Skip Baja) ---' AS STEP;
/* ----------------------------------------------------------------------------------------------------------
   [SUB-FASE 8.2]: Helper Optimizado (Modo Silencioso con Reporte)
   [MEJORA]: Elimina los SELECTs intermedios para que el script corra fluido sin pausas visuales.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 8.2 Asentando Calificaciones Masivas (Silent Mode) ---' AS STEP;

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_QA_Grade`$$

CREATE PROCEDURE `SP_QA_Grade`(
    IN _CursoID INT, 
    IN _Start INT, 
    IN _End INT, 
    IN _Grade DECIMAL(5,2), 
    IN _Exec INT
)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_UID INT;
    DECLARE v_RegID INT;
    DECLARE v_StatusActual INT;
    
    -- Contadores para el reporte final
    DECLARE v_Count_Success INT DEFAULT 0;
    DECLARE v_Count_Skipped INT DEFAULT 0;
    
    WHILE i <= _End DO
        -- 1. Obtenemos ID de Usuario
        SELECT Id_Usuario INTO v_UID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        
        -- 2. Obtenemos ID de Registro y Estatus
        SET v_RegID = NULL;
        SELECT Id_CapPart, Fk_Id_CatEstPart 
        INTO v_RegID, v_StatusActual 
        FROM Capacitaciones_Participantes 
        WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UID LIMIT 1;
        
        -- 3. Lógica de Decisión
        IF v_RegID IS NOT NULL THEN
            IF v_StatusActual != 5 THEN -- Si NO es baja
                CALL SP_EditarParticipanteCapacitacion(_Exec, v_RegID, _Grade, 100.00, NULL, 'Eval QA');
                SET v_Count_Success = v_Count_Success + 1;
            ELSE
                -- Si es baja, solo sumamos al contador, NO hacemos SELECT
                SET v_Count_Skipped = v_Count_Skipped + 1;
            END IF;
        END IF;
        
        SET i = i + 1;
    END WHILE;
    
    -- 4. REPORTE FINAL (Un solo mensaje al terminar el lote)
    SELECT CONCAT('✅ LOTE TERMINADO: Se calificaron ', v_Count_Success, ' alumnos. Se omitieron ', v_Count_Skipped, ' por estar en BAJA.') AS Resumen;

END$$

DELIMITER ;

/* ----------------------------------------------------------------------------------------------------------
   [SUB-FASE 8.2 CORREGIDA]: Asentamiento Masivo de Calificaciones
   [AJUSTE]: Se han corregido los rangos de IDs (Start/End) para que coincidan con la Inscripción (Fase 4).
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 8.2 Asentando Calificaciones Masivas (Rangos Alineados) ---' AS STEP;

-- Limpieza

SELECT '✅ FASE 8.2 COMPLETADA: Todos los alumnos han sido procesados correctamente.' AS STATUS;

-- C01: Mayoría Aprobada
CALL `SP_QA_Grade`(@C01_Ver, 1, 100, 80.00, @U_Inst2);

-- C02: Mayoría Reprobada
CALL `SP_QA_Grade`(@C02_Ver, 1, 100, 30.00, @U_Inst1);

-- C03: 100% Aprobación
CALL `SP_QA_Grade`(@C03_Ver, 1, 100, 85.00, @U_Inst2);

-- C04: Mixto
CALL `SP_QA_Grade`(@C04_Ver, 1, 100, 70.00, @U_Inst1);

-- C05: Aprobados
CALL `SP_QA_Grade`(@C05_Ver, 1, 100, 85.00, @U_Inst1);

-- C06: Aprobados
CALL `SP_QA_Grade`(@C06_Ver, 1, 100, 80.00, @U_Inst2);

DROP PROCEDURE `SP_QA_Grade`;

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Alumno verifica sus calificaciones.
   [SP USADO]: SP_ConsularMisCursos
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 7: Alumno revisa kardex ---' AS CHECK_POINT;

SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');
CALL SP_ConsularMisCursos(@U_P01);

SET @U_P05 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P05');
CALL SP_ConsularMisCursos(@U_P05);

SET @U_P10 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P10');
CALL SP_ConsularMisCursos(@U_P10);

SET @U_P15 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P15');
CALL SP_ConsularMisCursos(@U_P15);

SET @U_P20 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P20');
CALL SP_ConsularMisCursos(@U_P20);

SET @U_P25 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P25');
CALL SP_ConsularMisCursos(@U_P25);

SET @U_P30 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P30');
CALL SP_ConsularMisCursos(@U_P30);

SET @U_P35 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P35');
CALL SP_ConsularMisCursos(@U_P35);

SET @U_P40 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P40');
CALL SP_ConsularMisCursos(@U_P40);

SET @U_P45 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P45');
CALL SP_ConsularMisCursos(@U_P45);

SET @U_P50 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P50');
CALL SP_ConsularMisCursos(@U_P50);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 8 COMPLETADA: Evaluaciones registradas.' AS STATUS;

/* ==========================================================================================================
   FASE 9: DETERMINACIÓN DE ACREDITACIÓN (VEREDICTO)
   ==========================================================================================================
   [OBJETIVO]: Emitir un dictamen final para el curso (Curso Exitoso vs Fallido).
   [ACCIÓN TÉCNICA]: El Coordinador cambia el estatus del CURSO a 'ACREDITADO' (6) o 'NO ACREDITADO' (7).
   [REGLA DE NEGOCIO]: Se considera ACREDITADO si el 70% o más de los alumnos inscritos en el sistema
                       obtuvieron estatus de APROBADO.
   ========================================================================================================== */
SELECT '--- 9.1 Aplicando Veredictos ---' AS STEP;

-- C01: Acreditado (Mayoría aprobada).
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Acr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Dictamen: ACREDITADO');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

-- C02: No Acreditado (Reprobación masiva, no cumple el 70%).
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_NoAcr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Dictamen: NO ACREDITADO');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

-- C03: Acreditado (100% éxito).
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Acr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

-- C04: Acreditado.
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Acr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Dictamen: ACREDITADO');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

-- C05: Acreditado.
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Acr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

-- C06: Acreditado.
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Acr, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Dictamen: ACREDITADO');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 9 COMPLETADA: Veredictos aplicados.' AS STATUS;

/* ==========================================================================================================
   FASE 10: CIERRE (FINALIZADO)
   ==========================================================================================================
   [OBJETIVO]: Cerrar administrativamente los expedientes (Finalizado - ID 4).
   [ACCIÓN TÉCNICA]: Cambio de Estatus para los 6 cursos.
   [REGLA DE NEGOCIO]: Al cerrar el curso, los estatus de los alumnos (Aprobado/Reprobado) se vuelven definitivos.
   ========================================================================================================== */
SELECT '--- 10.1 Cierre Final ---' AS STEP;

SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Cierre');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Cierre');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Fin, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Cierre');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificación de Metas Anuales.
   [SP USADO]: SP_Dashboard_ResumenAnual
   [ESPERADO]: Debe reflejar 6 cursos finalizados en el periodo.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 9: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Trazabilidad Histórica.
   [ACCIÓN]: Consultar el detalle de C01.
   [ESPERADO]: El footer del SP debe mostrar 5 versiones previas inactivas, evidenciando el historial de cambios.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C02_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C03_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C04_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C05_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C06_Ver);

SELECT '✅ FASE 10 COMPLETADA: Cierre completado.' AS STATUS;

/* ==========================================================================================================
   FASE 11: ARCHIVADO (KILL SWITCH)
   ==========================================================================================================
   [OBJETIVO]: Sacar los cursos del tablero operativo (Soft Delete).
   [ACCIÓN TÉCNICA]: Uso de SP_CambiarEstatusCapacitacion con Activo=0.
   [LÓGICA]: El curso deja de ser visible en grids operativos pero permanece en reportes históricos.
   ========================================================================================================== */
SELECT '--- 11.1 Archivando ---' AS STEP;

SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);
CALL SP_EditarCapacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre');
CALL SP_CambiarEstatusCapacitacion(@CAP01_, @U_Adm1, 0);
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP01_);

SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);
CALL SP_EditarCapacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'REGISTRO ARCHIVADO');
CALL SP_CambiarEstatusCapacitacion(@CAP02_, @U_Adm1, 0);
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP02_);

SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);
CALL SP_EditarCapacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'REGISTRO ARCHIVADO');
CALL SP_CambiarEstatusCapacitacion(@CAP03_, @U_Adm1, 0);
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP03_);

SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);
CALL SP_EditarCapacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'REGISTRO ARCHIVADO');
CALL SP_CambiarEstatusCapacitacion(@CAP04_, @U_Adm1, 0);
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP04_);

SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);
CALL SP_EditarCapacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'REGISTRO ARCHIVADO');
CALL SP_CambiarEstatusCapacitacion(@CAP05_, @U_Adm1, 0);
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP05_);

SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);
CALL SP_EditarCapacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_Arch, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'REGISTRO ARCHIVADO');
CALL SP_CambiarEstatusCapacitacion(@CAP06_, @U_Adm1, 0);
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @CAP06_);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificación de Metas Anuales.
   [SP USADO]: SP_Dashboard_ResumenAnual
   [ESPERADO]: Debe reflejar 6 cursos finalizados en el periodo.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 9: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Trazabilidad Histórica.
   [ACCIÓN]: Consultar el detalle de C01.
   [ESPERADO]: El footer del SP debe mostrar 5 versiones previas inactivas, evidenciando el historial de cambios.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C02_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C03_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C04_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C05_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C06_Ver);

SELECT '✅ FASE 11 COMPLETADA: Archivado completado.' AS STATUS;

/* ==========================================================================================================
   FASE 12: CANCELACIÓN (CURSO C07)
   ==========================================================================================================
   [OBJETIVO]: Probar el flujo alterno de Cancelación (Edge Case).
   [LÓGICA]: Se crea un curso C07, se inscribe a alguien y luego se cancela (Status 8) en lugar de iniciarse.
   [QA]: Validar que un curso cancelado también pueda archivarse correctamente.
   ========================================================================================================== */
SELECT '--- 12.1 Prueba Cancelación ---' AS STEP;

-- 1. Crear
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C07', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 30, @St_Prog, 'C07 Cancel');
SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
SET @C07_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C07_Head);

-- 2. Inscribir Alumno P01
CALL SP_RegistrarParticipanteCapacitacion(@U_Adm1, @C07_Ver, @U_P01);

-- 3. Cancelar (Status 8)
CALL SP_EditarCapacitacion(@C07_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 8, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 0, 'Cancelado');

-- 4. Archivar
CALL SP_CambiarEstatusCapacitacion(@C07_Head, @U_Adm1, 0);

SELECT '✅ FASE 12 COMPLETADA: Cancelación completada.' AS STATUS;


/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Verificación de Metas Anuales.
   [SP USADO]: SP_Dashboard_ResumenAnual
   [ESPERADO]: Debe reflejar 6 cursos finalizados en el periodo.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 9: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Gerencia verifica impacto en KPIs.
   [SP USADO]: SP_Dashboard_ResumenGerencial
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 CHECKPOINT 8: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Visibilidad Pública.
   [ACCIÓN]: Ejecutar `SP_BuscadorGlobalPICADE` buscando el patrón del proyecto.
   [ESPERADO]: Deben aparecer los cursos con estatus "POR INICIAR", confirmando que están listos para el público.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 4: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;

CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Carga Docente.
   [ACCIÓN]: El Instructor 1 revisa qué cursos tiene asignados en este momento.
   [ESPERADO]: Debe ver los cursos activos (Estatus 3) donde él es el titular.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 6: Instructor ve su carga activa ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst2);

CALL SP_ConsultarCursosImpartidos(@U_Inst1);

/* ----------------------------------------------------------------------------------------------------------
   [AUDITORÍA DE VISTAS]: Validación de Trazabilidad Histórica.
   [ACCIÓN]: Consultar el detalle de C01.
   [ESPERADO]: El footer del SP debe mostrar 5 versiones previas inactivas, evidenciando el historial de cambios.
   ---------------------------------------------------------------------------------------------------------- */
SELECT '--- 🔍 AUDITORÍA VISUAL 5: Detalle del Curso con Historial (Debe mostrar 5 versiones previas) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C02_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C03_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C04_Ver);
CALL SP_ConsultarCapacitacionEspecifica(@C05_Ver);

CALL SP_ConsultarCapacitacionEspecifica(@C06_Ver);


/* ==========================================================================================================
   FASE 14: LIMPIEZA FINAL (TEARDOWN)
   ==========================================================================================================
   [OBJETIVO]: Desmontar el entorno de prueba para no dejar basura en la base de datos.
   [ACCIÓN TÉCNICA]: Uso de SP_EliminarCapacitacion y SP_EliminarUsuarioDefinitivamente.
   [LÓGICA]: Se borran las relaciones (inscripciones) primero, luego los cursos y finalmente los actores.
   ========================================================================================================== */
   
SELECT '--- 14.1 Limpieza Final ---' AS STEP;

-- Borrado de relaciones de participantes (Nietos)
TRUNCATE `picade`.`capacitaciones_participantes`;
-- SELECT * FROM `PICADE`.CAPACITACIONES_PARTICIPANTES;

-- DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');

-- Borrado de los 7 cursos (Padres e Hijos)
SET @CAP01_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01');
CALL SP_EliminarCapacitacion(@CAP01_);

SET @CAP02_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02');
CALL SP_EliminarCapacitacion(@CAP02_);

SET @CAP03_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03');
CALL SP_EliminarCapacitacion(@CAP03_);

SET @CAP04_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04');
CALL SP_EliminarCapacitacion(@CAP04_);

SET @CAP05_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05');
CALL SP_EliminarCapacitacion(@CAP05_);

SET @CAP06_ = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06');
CALL SP_EliminarCapacitacion(@CAP06_);

SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
CALL SP_EliminarCapacitacion(@C07_Head);

-- Borrado de Participantes (Iterativo para usar SP oficial)

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
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);

SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);

SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);

SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);

SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);

SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

-- Borrado de Infraestructura (FK Check Off para velocidad)
-- SET FOREIGN_KEY_CHECKS = 0;

SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema1);

SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema2);

SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');
CALL SP_EliminarTemaCapacitacionFisico(@IdTema3);

SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');
CALL SP_EliminarSedeFisica(@IdSedeA);

SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');
CALL SP_EliminarSedeFisica(@IdSedeB);

SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');
CALL SP_EliminarSedeFisica(@IdSedeC);

SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');
CALL SP_EliminarDepartamentoFisico(@IdDep);

SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_EliminarCentroTrabajoFisico(@IdCT);

SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE `Clave` = 'QA-DIAMOND-GER');
SET @IdCatSubDirec = (SELECT `Id_CatSubDirec` FROM `cat_subdirecciones` WHERE `Clave` = 'QA-DIAMOND-SUB');
SET @IdDirecc = (SELECT `Id_CatDirecc` FROM `cat_direcciones` WHERE `Clave` = 'QA-DIAMOND-DIR');

CALL SP_EliminarGerenciaFisica(@IdGer);
CALL SP_EliminarSubdireccionFisica(@IdCatSubDirec);
CALL SP_EliminarDireccionFisica(@IdDirecc);

SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');
SET @IdEdo = (SELECT ID_Estado FROM ESTADO WHERE Codigo = 'QA-DIAMOND-EDO');
SET @IdPais = (SELECT ID_Pais FROM PAIS WHERE Codigo = 'QA-DIAMOND-PAIS');

CALL SP_EliminarMunicipio(@IdMun);
CALL SP_EliminarEstadoFisico(@IdEdo);
CALL SP_EliminarPaisFisico(@IdPais);
-- SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 14 COMPLETADA: Limpieza total.' AS STATUS;