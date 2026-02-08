USE Picade;

/* =================================================================================
   SCRIPT MAESTRO DE VALIDACIÓN (QA) - PICADE
   MÓDULO: TEMAS DE CAPACITACIÓN + KILLSWITCH INTEGRAL
   VERSIÓN: DIAMOND STANDARD (FINAL)
   =================================================================================
   OBJETIVO: Validar CRUD completo, Vistas, Reglas de Negocio y Limpieza Total.
   
      DESCRIPCIÓN:
   Script maestro de validación automatizada (End-to-End). Simula el ciclo de vida completo de la
   entidad "Tema de Capacitación", sometiéndola a pruebas de estrés, integridad referencial y 
   bloqueos de lógica de negocio (Killswitch).

   FLUJO DE EJECUCIÓN:
   1. [SETUP]    Construcción de infraestructura (Mock Data: Geografía, Organización, RRHH).
   2. [CREATE]   Inyección de datos maestros (Happy Path & Negative Testing).
   3. [READ]     Validación de Vistas y Filtros de seguridad.
   4. [UPDATE]   Validación de idempotencia y conflictos de unicidad.
   5. [LOGIC]    Killswitch: Intento de baja lógica con dependencias activas (Bloqueo).
   6. [PHYSICAL] Hard Delete: Validación de integridad referencial histórica.
   7. [TEARDOWN] Limpieza quirúrgica y restauración del entorno (Bottom-Up Clean).

   NOTAS TÉCNICAS:
   - Requiere permisos de SUPER_ADMIN (@IdAdminGod).
   - Utiliza Store Procedures con manejo de transacciones ACID.
   - Las pruebas negativas están diseñadas para fallar controladamente (Error 400/409).
   ================================================================================= */

-- CONFIGURACIÓN DE ACTOR PRINCIPAL
SET @IdAdminGod = 322; -- ID del Super Administrador que ejecuta las pruebas

/* ---------------------------------------------------------------------------------
   SECCIÓN DE REFERENCIA: DATOS PRE-EXISTENTES (SOLO LECTURA)
   Estos datos YA EXISTEN en la BD. Se dejan aquí comentados por referencia.
   --------------------------------------------------------------------------------- */

/*
-- CATÁLOGO: MODALIDAD CAPACITACIÓN
INSERT INTO `Cat_Modalidad_Capacitacion` (Id_CatModalCap, Codigo, Nombre, Descripcion, Activo, created_at, updated_at) VALUES
(1, NULL, 'PRESENCIAL', 'CURSO 100% PRESENCIAL', 1),
(2, NULL, 'VIRTUAL', 'CURSO 100% EN LINEA', 1),
(3, NULL, 'DUAL/SEMIPRESENCIAL', 'PARTE VIRTUAL Y PARTE PRESENCIAL', 1);

-- CATÁLOGO: ESTATUS CAPACITACIÓN
INSERT INTO `Cat_Estatus_Capacitacion` (Id_CatEstCap, Nombre, Descripcion, Es_Final, Activo, created_at, updated_at) VALUES
(1, 'PROGRAMADO', 'CURSO CALENDARIZADO CON SEDE INSTRUCTOR Y LISTA PRELIMINAR', 0, 1, '2026-01-10 13:13:06', '2026-01-10 13:13:06'),
(2, 'POR INICIAR', 'PENDIENTE DE INICIO DETALLES CONFIRMADOS', 0, 1),
(3, 'EN CURSO', 'CURSO ACTUALMENTE EN IMPARTICION', 0, 1),
(4, 'FINALIZADO', 'CURSO IMPARTIDO EN SU TOTALIDAD', 1, 1),
(5, 'EN EVALUACION', 'EN PROCESO DE EVALUACION Y EVIDENCIAS', 0, 1),
(6, 'ACREDITADO', 'PARTICIPANTES HAN CUMPLIDO REQUISITOS MINIMOS', 1, 1),
(7, 'NO ACREDITADO', 'PARTICIPANTES NO CUMPLEN REQUISITOS MINIMOS', 1, 1),
(8, 'CANCELADO', 'CURSO CANCELADO ANTES DE INICIAR', 1, 1),
(9, 'REPROGRAMADO', 'CURSO REPROGRAMADO (FECHAS/SEDE/MODALIDAD)', 0, 1),
(10, 'CERRADO/ARCHIVADO', 'CURSO CON EXPEDIENTE COMPLETO Y ARCHIVADO', 1, 1);
*/

-- DEFINICIÓN DE VARIABLES DE ENTORNO
SET @IdModalPresencial = 1; -- PRESENCIAL
SET @IdEstProgramado = 1;   -- PROGRAMADO (Bloqueante)
SET @IdEstEnCurso = 3;      -- EN CURSO (Bloqueante)
SET @IdEstFinalizado = 4;   -- FINALIZADO (No Bloqueante)


/* =================================================================================
   FASE 0: CONSTRUCCIÓN DE INFRAESTRUCTURA (SANDBOX)
   ================================================================================= */
-- SELECT '--- FASE 0: INICIALIZANDO SANDBOX ---' AS LOG;

-- 0.1. GEOGRAFÍA
CALL SP_RegistrarUbicaciones('M_QA_TEM', 'MUNICIPIO TEMAS QA', 'E_QA_TEM', 'ESTADO TEMAS QA', 'P_QA_TEM', 'PAIS TEMAS QA');
SET @IdMunQA = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_TEM');

-- 0.2. ORGANIZACIÓN INTERNA
CALL SP_RegistrarOrganizacion('G_QA_TEM', 'GERENCIA TEMAS QA', 'S_QA_TEM', 'SUBDIRECCION TEMAS QA', 'D_QA_TEM', 'DIRECCION TEMAS QA');
SET @IdGerenQA = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_QA_TEM');

-- 0.3. INFRAESTRUCTURA FÍSICA
-- 0.3.1 SEDE (Para cursos)
CALL SP_RegistrarSede('CASES-QA-TEM', 'SEDE CAPACITACION QA', 'Calle Pruebas 123', @IdMunQA, 50, 2, 1, 0, 0, 0, 0);
SET @IdSedeQA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'CASES-QA-TEM');

-- 0.3.2 CENTRO DE TRABAJO (Para adscripción de personal)
-- Usamos tu SP robusto que maneja concurrencia y validaciones.
CALL SP_RegistrarCentroTrabajo('CT-QA-TEM', 'CENTRO DE TRABAJO QA', 'Av. Tecnológico #1', @IdMunQA);
SET @IdCentroTrabajoQA = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-QA-TEM');

-- 0.4. CATÁLOGOS LABORALES
CALL SP_RegistrarRegimen('REG-QA', 'REGIMEN QA', 'TEST');
SET @IdRegQA = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-QA');

CALL SP_RegistrarPuesto('PUE-INST', 'INSTRUCTOR DE CAMPO', 'TEST');
SET @IdPuestoQA = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-INST');

CALL SP_RegistrarRegion('RGN-QA', 'REGION QA', 'TEST');
SET @IdRegionQA = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'RGN-QA');

CALL SP_RegistrarDepartamento('DEP-CAP', 'CAPACITACION', 'OFICINA', @IdMunQA);
SET @IdDepQA = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-CAP');

-- 0.5. RECURSO HUMANO (EL ACTOR)
-- Registro mediante SP administrativo estricto (19 parámetros).
CALL SP_RegistrarUsuarioPorAdmin(
    @IdAdminGod,        -- _Id_Admin_Ejecutor
    'F-INST-QA',        -- _Ficha
    NULL,               -- _Url_Foto (Opcional v1.1)
    'PEDRO',            -- _Nombre
    'INSTRUCTOR',       -- _Apellido_Paterno
    'QA',               -- _Apellido_Materno
    '1980-01-01',       -- _Fecha_Nacimiento
    '2010-01-01',       -- _Fecha_Ingreso
    'inst_temas@qa.com',-- _Email
    '123',              -- _Contrasena
    3,                  -- _Id_Rol
    @IdRegQA,           -- _Id_Regimen
    @IdPuestoQA,        -- _Id_Puesto
    @IdCentroTrabajoQA, -- _Id_CentroTrabajo (Ahora sí tenemos el ID correcto)
    @IdDepQA,           -- _Id_Departamento
    @IdRegionQA,        -- _Id_Region
    @IdGerenQA,         -- _Id_Gerencia
    'N1',               -- _Nivel
    'C1'                -- _Clasificacion
);
SET @IdInstructorQA = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-INST-QA');

-- 0.6. CATÁLOGOS ACADÉMICOS (Padres de los Temas)
CALL SP_RegistrarTipoInstruccion('TÉCNICO OPERATIVO QA', 'Cursos de operación en campo');
SET @IdTipoTecnico = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'TÉCNICO OPERATIVO QA');

CALL SP_RegistrarTipoInstruccion('SEGURIDAD SSPA QA', 'Normatividad de seguridad');
SET @IdTipoSeguridad = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'SEGURIDAD SSPA QA');

/* =================================================================================
   FASE 1: REGISTRO DE TEMAS (CREATE & SEEDING)
   Objetivo: Crear datos maestros para pruebas de integridad, borrado y reportes.
   ================================================================================= */
-- SELECT '--- FASE 1: REGISTRO DE TEMAS ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. CASOS DE ÉXITO (Happy Path)
-- ---------------------------------------------------------------------------------

-- 1.1. Registrar Tema "Víctima" (CASO: Integridad Referencial)
CALL SP_RegistrarTemaCapacitacion('TEMA-KILL-01', 'SEGURIDAD BASICA SSPA', 'Tema crítico con cursos activos para prueba de candado', 20, @IdTipoTecnico);
SET @IdTemaVictima = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-KILL-01');

-- 1.2. Registrar Tema "Limpio" (CASO: Borrado Exitoso)
CALL SP_RegistrarTemaCapacitacion('TEMA-CLEAN-02', 'INTRODUCCION A LA CALIDAD', 'Tema huerfano para prueba de borrado limpio', 8, @IdTipoTecnico);
SET @IdTemaLimpio = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-CLEAN-02');

-- 1.3. Registrar Tema "Estándar" (CASO: Modificación y Auditoría)
CALL SP_RegistrarTemaCapacitacion('TEMA-UPD-03', 'OPERACION DE EQUIPOS CRITICOS', 'Tema destinado a sufrir modificaciones de nombre y horas', 40, @IdTipoTecnico);
SET @IdTemaUpdate = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-UPD-03');

-- 1.4. Registrar Tema "Reportes" (CASO: Agrupación de Datos)
CALL SP_RegistrarTemaCapacitacion('TEMA-REP-04', 'LIDERAZGO Y GESTION', 'Tema soft-skill para validación de reportes mixtos', 16, @IdTipoTecnico);
SET @IdTemaReporte = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-REP-04');

-- ---------------------------------------------------------------------------------
-- B. PRUEBAS DE ERROR (Negative Testing)
-- ---------------------------------------------------------------------------------

-- 1.5. Prueba de Error: Campos Obligatorios
CALL SP_RegistrarTemaCapacitacion(NULL, 'SIN CODIGO', 'Desc', 0, @IdTipoTecnico); 

-- 1.6. Prueba de Error: Duplicidad
CALL SP_RegistrarTemaCapacitacion('TEMA-KILL-01', 'NOMBRE DUPLICADO', 'Intento de duplicado', 20, @IdTipoTecnico); 

-- ---------------------------------------------------------------------------------
-- C. VERIFICACIÓN FINAL
-- ---------------------------------------------------------------------------------
-- SELECT * FROM Cat_Temas_Capacitacion ORDER BY Id_Cat_TemasCap DESC LIMIT 5;


/* =================================================================================
   FASE 2: LECTURA Y VISTAS (READ)
   ================================================================================= */
-- SELECT '--- FASE 2: LECTURA DE CATÁLOGOS ---' AS LOG;

-- 2.1. Listado Completo para Administrador
CALL SP_ListarTemasAdmin();

-- 2.2. Listado Filtrado para Dropdowns
CALL SP_ListarTemasActivos();

-- 2.3. Consulta de Detalle Específico
CALL SP_ConsultarTemaCapacitacionEspecifico(@IdTemaVictima);


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD (UPDATE)
   Objetivo: Validar cada cláusula IF del SP_EditarTemaCapacitacion
   ================================================================================= */
-- SELECT '--- FASE 3: EDICIÓN ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. PRUEBAS DE VALIDACIÓN DE ENTRADA (Input Validation)
-- ---------------------------------------------------------------------------------

-- 3.1. ID Inválido
-- Esperado: ERROR DE SISTEMA [400]
CALL SP_EditarTemaCapacitacion(0, 'CODE', 'NAME', 'Desc', 10, @IdTipoTecnico);

-- 3.2. Código Nulo
-- Esperado: ERROR DE VALIDACIÓN [400]
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, NULL, 'NAME', 'Desc', 10, @IdTipoTecnico);

-- 3.3. Nombre Nulo
-- Esperado: ERROR DE VALIDACIÓN [400]
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', NULL, 'Desc', 10, @IdTipoTecnico);

-- 3.4. Duración Inválida
-- Esperado: ERROR DE VALIDACIÓN [400]
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'NAME', 'Desc', 0, @IdTipoTecnico);

-- 3.5. Tipo Instrucción Inválido
-- Esperado: ERROR DE VALIDACIÓN [400]
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'NAME', 'Desc', 10, 0);

-- ---------------------------------------------------------------------------------
-- B. PRUEBAS DE LÓGICA DE NEGOCIO E INTEGRIDAD
-- ---------------------------------------------------------------------------------

-- 3.6. Edición de Registro Inexistente
-- Esperado: ERROR CRÍTICO [404]
CALL SP_EditarTemaCapacitacion(99999, 'FANTASMA', 'Fantasma', 'Desc', 10, @IdTipoTecnico);

-- 3.7. Integridad Referencial - Padre No Existe
-- Esperado: ERROR DE INTEGRIDAD [404]
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'Test FK', 'Desc', 10, 999);

-- 3.8. Conflicto de Código Único
-- Esperado: CONFLICTO DE DATOS [409]
CALL SP_EditarTemaCapacitacion(@IdTemaLimpio, 'TEMA-KILL-01', 'INTENTO ROBO', 'Desc', 10, @IdTipoTecnico);

-- ---------------------------------------------------------------------------------
-- C. CASOS DE COMPORTAMIENTO ESPERADO (Happy Path)
-- ---------------------------------------------------------------------------------

-- 3.9. Detección de "Sin Cambios"
-- Esperado: AVISO: No se detectaron cambios (SIN_CAMBIOS)
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'SEGURIDAD BASICA SSPA', 'Tema crítico con cursos activos para prueba de candado', 20, @IdTipoTecnico);

-- 3.10. Edición Exitosa
-- Esperado: Mensaje de éxito estándar.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'SEGURIDAD BASICA SSPA (V2)', 'Actualizado tras revisión anual', 24, @IdTipoTecnico);

-- ---------------------------------------------------------------------------------
-- D. VERIFICACIÓN POST-TEST
-- ---------------------------------------------------------------------------------
/*SELECT Id_Cat_TemasCap, Codigo, Nombre, Duracion_Horas, created_to, updated_to 
FROM Cat_Temas_Capacitacion 
WHERE Id_Cat_TemasCap = @IdTemaVictima;*/


/* ====================================================================================================
   FASE 4: CAMBIO DE ESTATUS, KILLSWITCH Y REGLAS DE JERARQUÍA (DIAMOND STANDARD)
   OBJETIVO: Validar la integridad descendente (Killswitch) y ascendente (Jerarquía).
   ==================================================================================================== */
SELECT '>>> INICIANDO FASE 4: KILLSWITCH Y REGLAS DE NEGOCIO <<<' AS LOG_STEP;

-- ---------------------------------------------------------------------------------
-- A. VALIDACIONES DE ENTRADA (FAIL-FAST)
-- ---------------------------------------------------------------------------------

-- 4.1. ID Inválido: Se envía ID 0. [ESPERADO]: ERROR 400.
 CALL SP_CambiarEstatusTemaCapacitacion(0, 0);

-- 4.2. Estatus Inválido: Se envía estatus 5. [ESPERADO]: ERROR 400.
 CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 5);

-- 4.3. Tema Inexistente: ID fuera de rango. [ESPERADO]: ERROR 404.
 CALL SP_CambiarEstatusTemaCapacitacion(99999, 0);

-- ---------------------------------------------------------------------------------
-- B. PRUEBA DEL "KILLSWITCH" (CONFLICTO OPERATIVO)
-- ---------------------------------------------------------------------------------

-- 4.4. Preparar Escenario: Crear Cabecera de Capacitación
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo, created_at, updated_at) 
VALUES ('FOLIO-KILL-001', @IdGerenQA, @IdTemaVictima, 15, 1, NOW(), NOW());
SET @IdCapKill = LAST_INSERT_ID();

-- 4.5. Asignar Estatus "EN CURSO" (ID 3 - Bloqueante)
INSERT INTO `DatosCapacitaciones` (Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones, created_at, updated_at) 
VALUES (@IdCapKill, @IdInstructorQA, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 DAY), @IdSedeQA, @IdModalPresencial, @IdEstEnCurso, 1, 'Prueba Killswitch', NOW(), NOW()); 

-- 4.6. INTENTO DE DESACTIVACIÓN ILEGAL
-- El tema tiene un curso activo en este momento. El SP debe denegar el acceso.
-- [ESPERADO]: CONFLICTO OPERATIVO [409]
-- SELECT 'PRUEBA 4.6: Intento desactivar tema con curso EN CURSO (Debe Fallar)' AS Test_Scenario;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- ---------------------------------------------------------------------------------
-- C. LIBERACIÓN DE CANDADO Y BAJA LÓGICA
-- ---------------------------------------------------------------------------------

-- 4.7. Evolución del Curso (Liberación del Candado)
-- Cambiamos a estatus 'FINALIZADO' (ID 4), el cual no bloquea al tema.
UPDATE `DatosCapacitaciones` 
SET Fk_Id_CatEstCap = @IdEstFinalizado, Observaciones = 'Curso finalizado, liberando tema', updated_at = NOW()
WHERE Fk_Id_Capacitacion = @IdCapKill AND Activo = 1;

-- 4.8. DESACTIVACIÓN LEGAL (ÉXITO)
-- [ESPERADO]: Mensaje 'ÉXITO: El Tema ha sido DESACTIVADO'.
-- SELECT 'PRUEBA 4.8: Desactivación con curso Finalizado (Debe Funcionar)' AS Test_Scenario;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- ---------------------------------------------------------------------------------
-- D. VALIDACIÓN DE JERARQUÍA (PADRE INACTIVO)
-- ---------------------------------------------------------------------------------

-- 4.9.A. PREPARACIÓN: DESACTIVAR A TODOS LOS HIJOS (TU PROPUESTA)
-- Para que el Padre acepte desactivarse, sus otros hijos registrados también deben estar en 0.
-- SELECT 'PASO 4.9.A: Preparando desactivación del Padre (Apagando Hermanos)...' AS Test_Scenario;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaLimpio, 0);
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaUpdate, 0);
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaReporte, 0);

-- 4.9.B. DESACTIVAR AL PADRE (USANDO SP)
-- Ahora que no hay ningún hijo activo ligado a este Tipo de Instrucción, el SP debe permitirlo.
-- [ESPERADO]: ÉXITO 'ESTATUS_CAMBIADO'.
-- SELECT 'PRUEBA 4.9.B: Desactivar Padre sin hijos activos (Debe Funcionar)' AS Test_Scenario;
CALL SP_CambiarEstatusTipoInstruccion(@IdTipoTecnico, 0);

-- 4.10. INTENTO DE REACTIVACIÓN HUÉRFANA (LA PRUEBA MAESTRA)
-- Intentamos activar al hijo 'Victima', pero el SP debe detectar que el Padre está en 0.
-- [ESPERADO]: ERROR DE INTEGRIDAD [409]: Reactive la categoría primero.
-- SELECT 'PRUEBA 4.10: Reactivar Tema con Padre Inactivo (Debe Fallar)' AS Test_Scenario;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 1);

-- ---------------------------------------------------------------------------------
-- E. RESTAURACIÓN DEL ENTORNO PARA FASES POSTERIORES
-- ---------------------------------------------------------------------------------

-- 4.11. Restaurar Padre (Tipo de Instrucción)
CALL SP_CambiarEstatusTipoInstruccion(@IdTipoTecnico, 1);

-- 4.12. Restaurar Hijos (Temas)
-- Encendemos todos para que la Fase 5 y 6 puedan procesarlos.
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 1);
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaLimpio, 1);
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaUpdate, 1);
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaReporte, 1);

-- SELECT '>>> FASE 4 FINALIZADA CORRECTAMENTE <<<' AS RESULTADO;

/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   ================================================================================= */
-- SELECT '--- FASE 5: ELIMINACIÓN FÍSICA ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. VALIDACIONES DE ENTRADA
-- ---------------------------------------------------------------------------------

-- 5.1. ID Inválido
-- Esperado: ERROR DE SISTEMA [400]
CALL SP_EliminarTemaCapacitacionFisico(0);

-- ---------------------------------------------------------------------------------
-- B. VALIDACIÓN DE EXISTENCIA
-- ---------------------------------------------------------------------------------

-- 5.2. Tema Inexistente
-- Esperado: ERROR DE NEGOCIO [404]
CALL SP_EliminarTemaCapacitacionFisico(99999);

-- ---------------------------------------------------------------------------------
-- C. PRUEBA DE BLOQUEO DE NEGOCIO (INTEGRIDAD REFERENCIAL LÓGICA)
-- ---------------------------------------------------------------------------------

-- 5.3. Intento de Borrado con Historial
-- Esperado: BLOQUEO DE NEGOCIO [409]
-- SELECT 'PRUEBA 5.3: Eliminación de Tema con Historial (Debe Fallar)' AS Test_Step;
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaVictima);

-- ---------------------------------------------------------------------------------
-- D. CASO DE ÉXITO (HAPPY PATH)
-- ---------------------------------------------------------------------------------

-- 5.4. Borrado Físico de Tema Limpio
-- Esperado: Mensaje de éxito "ELIMINADA".
-- SELECT 'PRUEBA 5.4: Eliminación de Tema Virgen (Debe Funcionar)' AS Test_Step;
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaLimpio);

-- ---------------------------------------------------------------------------------
-- E. VERIFICACIÓN FINAL
-- ---------------------------------------------------------------------------------
/*SELECT Id_Cat_TemasCap, Codigo, Nombre, Activo 
FROM Cat_Temas_Capacitacion 
WHERE Id_Cat_TemasCap IN (@IdTemaVictima, @IdTemaLimpio);*/


/* =================================================================================
   FASE 6: LIMPIEZA TOTAL (TEARDOWN) - REINICIO DE ENTORNO
   Objetivo: Eliminar CADA registro creado durante las pruebas.
   Orden: De Hijos a Padres (Bottom-Up) para respetar la Integridad Referencial.
   ================================================================================= */
-- SELECT '--- FASE 6: LIMPIEZA DE ENTORNO (TEARDOWN) ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- 6.1. LIMPIEZA TRANSACCIONAL (Nivel más bajo)
-- ---------------------------------------------------------------------------------
-- Eliminamos los datos de la capacitación de prueba si aún existen
DELETE FROM `DatosCapacitaciones` WHERE Fk_Id_Capacitacion = @IdCapKill;
DELETE FROM `Capacitaciones` WHERE Id_Capacitacion = @IdCapKill;

-- ---------------------------------------------------------------------------------
-- 6.2. LIMPIEZA DE TEMAS (Hijos de Tipos de Instrucción)
-- ---------------------------------------------------------------------------------
-- Borramos los temas que quedaron vivos (Victima, Update, Reporte). 
-- 'Tema Limpio' ya fue borrado en la Fase 5.
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaVictima); 
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaUpdate);
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaReporte);

-- ---------------------------------------------------------------------------------
-- 6.3. LIMPIEZA DE CATÁLOGOS ACADÉMICOS (Padres de Temas)
-- ---------------------------------------------------------------------------------
CALL SP_EliminarTipoInstruccionFisico(@IdTipoTecnico);
CALL SP_EliminarTipoInstruccionFisico(@IdTipoSeguridad);

-- ---------------------------------------------------------------------------------
-- 6.4. LIMPIEZA DE RECURSOS HUMANOS (Usuarios y Dependencias)
-- ---------------------------------------------------------------------------------
-- Eliminamos al Instructor (Esto borra Usuario e Info_Personal en cascada controlada)
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdInstructorQA);

-- Ahora que no hay empleados, podemos borrar los catálogos laborales asociados
CALL SP_EliminarDepartamentoFisico(@IdDepQA);
CALL SP_EliminarPuestoFisico(@IdPuestoQA);
CALL SP_EliminarRegimenFisico(@IdRegQA);
CALL SP_EliminarRegionFisica(@IdRegionQA);

-- ---------------------------------------------------------------------------------
-- 6.5. LIMPIEZA DE INFRAESTRUCTURA FÍSICA
-- ---------------------------------------------------------------------------------
CALL SP_EliminarSedeFisica(@IdSedeQA); 

-- ---------------------------------------------------------------------------------
-- 6.6. LIMPIEZA DE ORGANIZACIÓN (Jerarquía: Gerencia -> Subdirección -> Dirección)
-- ---------------------------------------------------------------------------------
-- 1. Eliminamos Gerencia (Variable ya existente)
CALL SP_EliminarGerenciaFisica(@IdGerenQA);

-- 2. Eliminamos Subdirección (Recuperamos ID por Clave antes de borrar)
SET @IdSubQA = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'S_QA_TEM');
CALL SP_EliminarSubdireccionFisica(@IdSubQA);

-- 3. Eliminamos Dirección (Recuperamos ID por Clave antes de borrar)
SET @IdDirQA = (SELECT Id_CatDirecc FROM Cat_Direcciones WHERE Clave = 'D_QA_TEM');
CALL SP_EliminarDireccionFisica(@IdDirQA);

-- ---------------------------------------------------------------------------------
-- 6.7. LIMPIEZA DE GEOGRAFÍA (Jerarquía: Municipio -> Estado -> País)
-- ---------------------------------------------------------------------------------
-- Limpieza forzada de hijos del municipio
DELETE FROM Cat_Departamentos WHERE Fk_Id_Municipio_CatDep = @IdMunQA;
DELETE FROM Cat_Centros_Trabajo WHERE Fk_Id_Municipio_CatCT = @IdMunQA;
DELETE FROM Cat_Cases_Sedes WHERE Fk_Id_Municipio = @IdMunQA;

-- Intenta el municipio de nuevo
-- 1. Eliminamos Municipio (Variable ya existente)
CALL SP_EliminarMunicipio(@IdMunQA);

-- 2. Eliminamos Estado (Recuperamos ID por Código antes de borrar)
SET @IdEdoQA = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_TEM');
CALL SP_EliminarEstadoFisico(@IdEdoQA);

-- 3. Eliminamos País (Recuperamos ID por Código antes de borrar)
SET @IdPaisQA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_TEM');
CALL SP_EliminarPaisFisico(@IdPaisQA);

-- ---------------------------------------------------------------------------------
-- CONFIRMACIÓN FINAL
-- ---------------------------------------------------------------------------------
SELECT 'PRUEBAS QA FINALIZADAS Y ENTORNO RESTAURADO AL 100%' AS Estatus_Final;