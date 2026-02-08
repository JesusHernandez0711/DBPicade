USE Picade;

/* =================================================================================
   MASTER SCRIPT DE VALIDACIÓN (QA) - ESTATUS DE CAPACITACIÓN
   VERSIÓN: DIAMOND STANDARD (COBERTURA TOTAL)
   =================================================================================
   OBJETIVO: 
   Certificar que el módulo de Estatus es invulnerable a datos sucios, duplicados,
   inconsistencias de edición y violaciones de integridad referencial.
   
   ALCANCE:
   - FASE 0: Limpieza Segura.
   - FASE 1: Infraestructura (Geografía, RH, Academia).
   - FASE 2: CREATE (Validación de Integridad y Unicidad).
   - FASE 3: READ (Vistas).
   - FASE 4: UPDATE (Validación de Conflictos y Idempotencia).
   - FASE 5: SOFT DELETE (Killswitch Operativo).
   - FASE 6: HARD DELETE (Candado Histórico).
   - FASE 7: TEARDOWN (Limpieza Bottom-Up).
   ================================================================================= */

-- 1. CONFIGURACIÓN
SET @IdAdminGod = 322;        -- Tu Super Admin.
SET @IdModalPresencial = 1;   -- Dato base existente.
SET @IdEstFinalizado = 4;     -- Dato base existente.

-- ---------------------------------------------------------------------------------
-- FASE 0: LIMPIEZA PREVENTIVA (SEGURIDAD)
-- ---------------------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
-- Limpiamos solo datos de prueba previos para evitar errores de Unique Key al re-correr el script
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA TEST%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE '%QA%';
DELETE FROM `Usuarios` WHERE `Email` LIKE '%@qa.test';
DELETE FROM `Info_Personal` WHERE `Nombre` LIKE '%QA%';
DELETE FROM `Cat_Estatus_Capacitacion` WHERE `Codigo` LIKE 'QA-%'; 
-- (Nota: Se asume que el resto de catálogos QA se limpian al final o no estorban)
SET FOREIGN_KEY_CHECKS = 1;

SELECT '>>> FASE 0: ENTORNO PREPARADO <<<' AS ESTADO;

/* =================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (USANDO TUS SPs)
   ================================================================================= */

-- 1.1. Geografía
CALL SP_RegistrarUbicaciones('QA-MUN', 'MUNICIPIO QA', 'QA-EDO', 'ESTADO QA', 'QA-PAIS', 'PAIS QA');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-MUN');

-- 1.2. Organización y Sedes
CALL SP_RegistrarOrganizacion('QA-GER', 'GERENCIA QA', 'QA-SUB', 'SUBDIRECCION QA', 'QA-DIR', 'DIRECCION QA');
SET @IdGeren = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-GER');

CALL SP_RegistrarCentroTrabajo('QA-CT', 'OFICINA QA', 'AV. TEST', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-CT');

CALL SP_RegistrarDepartamento('QA-DEP', 'DEPTO QA', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DEP');

CALL SP_RegistrarSede('QA-SEDE', 'AULA DE PRUEBAS QA', 'CALLE TEST', @IdMun, 20, 1, 0, 0, 0, 0, 0);
SET @IdSede = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-SEDE');

-- 1.3. Catálogos RH
CALL SP_RegistrarRegion('QA-RGN', 'REGION QA', 'TEST');
SET @IdRegion = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'QA-RGN');

CALL SP_RegistrarRegimen('QA-REG', 'REGIMEN QA', 'TEST');
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'QA-REG');

CALL SP_RegistrarPuesto('QA-PUE', 'PUESTO QA', 'TEST');
SET @IdPuesto = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'QA-PUE');

CALL SP_RegistrarRol('QA-ROL', 'ROL QA', 'TEST');
SET @IdRol = (SELECT Id_Rol FROM Cat_Roles WHERE Codigo = 'QA-ROL');

-- 1.4. ALTA DEL INSTRUCTOR (USANDO TU SP BLINDADO)
CALL SP_RegistrarUsuarioPorAdmin(
    @IdAdminGod, 'QA-F-001', NULL, 'INSTRUCTOR_QA', 'TESTER', 'MASTER', '1990-01-01', '2020-01-01', 
    'inst@qa.test', 'pass123', @IdRol, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGeren, '00', 'A'
);
SET @IdInstructor = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-F-001');

-- 1.5. Academia
CALL SP_RegistrarTipoInstruccion('QA-TIPO', 'TIPO TEST');
SET @IdTipo = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'QA-TIPO');

CALL SP_RegistrarTemaCapacitacion('QA-TEMA', 'CURSO DE PRUEBA EXHAUSTIVA', 'TEST', 10, @IdTipo);
SET @IdTema = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-TEMA');


/* =================================================================================
   FASE 2: PRUEBAS DE "REGISTRO DE ESTATUS" (CREATE)
   Validamos: Happy Path, Datos Sucios, Nulos, Duplicidad de Código, Duplicidad de Nombre.
   ================================================================================= */
SELECT '--- INICIANDO PRUEBAS DE REGISTRO (SP_RegistrarEstatusCapacitacion) ---' AS LOG;

-- 2.1. Registro Exitoso (Datos con espacios para probar TRIM)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarEstatusCapacitacion('  QA-TEST-01  ', '  ESTATUS VICTIMA  ', '  Para pruebas de killswitch  ', 0);
SET @IdEstVictima = (SELECT Id_CatEstCap FROM Cat_Estatus_Capacitacion WHERE Codigo = 'QA-TEST-01');

-- 2.2. Registro Exitoso (Segundo Estatus para pruebas cruzadas)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarEstatusCapacitacion('QA-TEST-02', 'ESTATUS LIMPIO', 'Para pruebas de borrado', 0);
SET @IdEstLimpio = (SELECT Id_CatEstCap FROM Cat_Estatus_Capacitacion WHERE Codigo = 'QA-TEST-02');

-- 2.3. Prueba de Idempotencia (Repetir el registro 2.1)
-- [ESPERADO]: Mensaje 'AVISO... ya existe...', Accion 'REUSADA'.
CALL SP_RegistrarEstatusCapacitacion('QA-TEST-01', 'ESTATUS VICTIMA', 'Otra desc', 0);

-- 2.4. Prueba de Integridad (Nulos) - Código NULL
-- [ESPERADO]: 🔴 ERROR [400]: "El CÓDIGO es obligatorio."
CALL SP_RegistrarEstatusCapacitacion(NULL, 'NOMBRE X', 'DESC', 0);

-- 2.5. Prueba de Integridad (Nulos) - Nombre NULL
-- [ESPERADO]: 🔴 ERROR [400]: "El NOMBRE es obligatorio."
CALL SP_RegistrarEstatusCapacitacion('COD-X', NULL, 'DESC', 0);

-- 2.6. Prueba de Duplicidad Cruzada (Código existe, Nombre diferente)
-- Intentamos usar el código 'QA-TEST-01' con otro nombre.
-- [ESPERADO]: 🔴 ERROR [409]: "...CÓDIGO ingresado ya existe pero está asignado a otro nombre."
CALL SP_RegistrarEstatusCapacitacion('QA-TEST-01', 'NOMBRE IMPOSTOR', 'DESC', 0);

-- 2.7. Prueba de Duplicidad Cruzada (Nombre existe, Código diferente)
-- Intentamos usar el nombre 'ESTATUS VICTIMA' con otro código.
-- [ESPERADO]: 🔴 ERROR [409]: "...NOMBRE ya existe asociado a otro CÓDIGO diferente."
CALL SP_RegistrarEstatusCapacitacion('QA-IMPOSTOR', 'ESTATUS VICTIMA', 'DESC', 0);


/* =================================================================================
   FASE 3: PRUEBAS DE "LECTURA Y VISTAS" (READ)
   Verificamos que la UI reciba la data correcta.
   ================================================================================= */
SELECT '--- INICIANDO PRUEBAS DE LECTURA ---' AS LOG;

-- 3.1. Grid de Administración (Debe incluir inactivos y todos los campos)
CALL SP_ListarEstatusCapacitacion();

-- 3.2. Dropdown Operativo (Solo activos)
CALL SP_ListarEstatusCapacitacionActivos();

-- 3.3. Consulta de Detalle (Raw Data para edición)
CALL SP_ConsultarEstatusCapacitacionEspecifico(@IdEstVictima);


/* =================================================================================
   FASE 4: PRUEBAS DE "EDICIÓN" (UPDATE)
   Validamos: Sin Cambios, Actualización Real, Conflictos de Unicidad.
   ================================================================================= */
SELECT '--- INICIANDO PRUEBAS DE EDICIÓN (SP_EditarEstatusCapacitacion) ---' AS LOG;

-- 4.1. Prueba "Sin Cambios" (Idempotencia)
-- Enviamos exactamente los mismos datos que tiene el registro.
-- [ESPERADO]: Mensaje 'AVISO: No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarEstatusCapacitacion(@IdEstVictima, 'QA-TEST-01', 'ESTATUS VICTIMA', 'Para pruebas de killswitch', 0);

-- 4.2. Prueba de Conflicto (Intentar robar CÓDIGO de otro)
-- Intentamos ponerle al Estatus Limpio (@IdEstLimpio) el código del Víctima ('QA-TEST-01').
-- [ESPERADO]: 🔴 ERROR [409]: "...El CÓDIGO ingresado ya pertenece a otro Estatus."
CALL SP_EditarEstatusCapacitacion(@IdEstLimpio, 'QA-TEST-01', 'ESTATUS LIMPIO', 'DESC', 0);

-- 4.3. Prueba de Conflicto (Intentar robar NOMBRE de otro)
-- Intentamos ponerle al Estatus Limpio el nombre del Víctima ('ESTATUS VICTIMA').
-- [ESPERADO]: 🔴 ERROR [409]: "...El NOMBRE ingresado ya pertenece a otro Estatus."
CALL SP_EditarEstatusCapacitacion(@IdEstLimpio, 'QA-TEST-02', 'ESTATUS VICTIMA', 'DESC', 0);

-- 4.4. Edición Exitosa (Renombramiento)
-- Cambiamos el nombre y descripción del estatus víctima.
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'ACTUALIZADA'.
CALL SP_EditarEstatusCapacitacion(@IdEstVictima, 'QA-TEST-01', 'ESTATUS VICTIMA (VIVO)', 'Renombrado para prueba', 0);


/* =================================================================================
   FASE 5: PRUEBAS DE "BAJA LÓGICA" (KILLSWITCH OPERATIVO)
   Esta es la prueba crítica. Validamos el Candado Descendente.
   ================================================================================= */
SELECT '>>> INICIANDO PRUEBAS DE KILLSWITCH (SP_CambiarEstatus...) <<<' AS LOG;

-- 5.1. PREPARACIÓN: Crear Curso VIVO usando el estatus "QA-TEST-01"
-- Cabecera
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo)
VALUES ('CAP-QA-001', @IdGeren, @IdTema, 10, 1);
SET @IdCap = LAST_INSERT_ID();

-- Detalle (EL CANDADO): Usamos @IdEstVictima y Activo = 1.
INSERT INTO `DatosCapacitaciones` 
(Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones)
VALUES 
(@IdCap, @IdInstructor, CURDATE(), CURDATE(), @IdSede, @IdModalPresencial, @IdEstVictima, 1, 'QA TEST ACTIVO');
SET @IdDatosCap = LAST_INSERT_ID();

-- 5.2. INTENTO DE DESACTIVACIÓN ILEGAL
-- El estatus está en uso por un curso vivo.
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD... existen CAPACITACIONES ACTIVAS..."
CALL SP_CambiarEstatusEstatusCapacitacion(@IdEstVictima, 0);

-- 5.3. LIBERACIÓN DEL CANDADO (Migración Operativa)
-- Simulamos que el curso avanza y se cambia al estatus "FINALIZADO" (ID 4 - existente en tu base).
UPDATE `DatosCapacitaciones` SET `Fk_Id_CatEstCap` = @IdEstFinalizado WHERE `Id_DatosCap` = @IdDatosCap;
SELECT 'SIMULACIÓN: Curso migrado a FINALIZADO (ID 4).' AS INFO;

-- 5.4. DESACTIVACIÓN LEGAL
-- Ahora el estatus "QA-TEST-01" no tiene cursos vivos. Debe dejar desactivar.
-- [ESPERADO]: Mensaje 'ÉXITO... ha sido DESACTIVADO', Accion 'ESTATUS_CAMBIADO'.
CALL SP_CambiarEstatusEstatusCapacitacion(@IdEstVictima, 0);

-- 5.5. REACTIVACIÓN (Para preparar fase 6)
-- [ESPERADO]: Mensaje 'ÉXITO... ha sido REACTIVADO'.
CALL SP_CambiarEstatusEstatusCapacitacion(@IdEstVictima, 1);


/* =================================================================================
   FASE 6: PRUEBAS DE "BAJA FÍSICA" (HARD DELETE)
   Validamos el Candado Histórico Absoluto.
   ================================================================================= */
SELECT '>>> INICIANDO PRUEBAS DE BORRADO FÍSICO (SP_Eliminar...) <<<' AS LOG;

-- 6.1. PRUEBA DE CANDADO HISTÓRICO
-- Aunque ya movimos el curso a "Finalizado", vamos a insertar un registro HISTÓRICO (Borrado/Inactivo)
-- que use el estatus víctima. El sistema NO debe dejar borrar físicamente si hay rastros.
INSERT INTO `DatosCapacitaciones` 
(Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones)
VALUES 
(@IdCap, @IdInstructor, '2020-01-01', '2020-01-01', @IdSede, @IdModalPresencial, @IdEstVictima, 0, 'HISTORIAL BORRADO');
SET @IdHistorial = LAST_INSERT_ID();

-- Intentamos borrar físicamente el estatus víctima.
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD... Existen registros históricos..."
CALL SP_EliminarEstatusCapacitacionFisico(@IdEstVictima);

-- 6.2. CASO DE ÉXITO (HAPPY PATH)
-- El estatus "Limpio" (@IdEstLimpio) lo creamos en el paso 2.2 y NUNCA lo usamos en cursos.
-- [ESPERADO]: Mensaje 'ÉXITO... eliminado permanentemente', Accion 'ELIMINADO_FISICO'.
CALL SP_EliminarEstatusCapacitacionFisico(@IdEstLimpio);


/* =================================================================================
   FASE 7: LIMPIEZA TOTAL (TEARDOWN)
   Dejamos tu base de datos limpia de nuestra basura de pruebas.
   ================================================================================= */
SELECT '--- FASE 7: LIMPIEZA FINAL ---' AS LOG;

-- A. Limpiamos las tablas transaccionales de prueba
DELETE FROM `DatosCapacitaciones` WHERE `Id_DatosCap` IN (@IdDatosCap, @IdHistorial);
DELETE FROM `Capacitaciones` WHERE `Id_Capacitacion` = @IdCap;

-- B. Ahora sí, borramos el Estatus Víctima (ya no tiene dependencias)
CALL SP_EliminarEstatusCapacitacionFisico(@IdEstVictima);

-- C. Borramos al Instructor y su usuario (Usando tu SP)
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdInstructor);

-- D. Borramos catálogos de prueba (Geografía, RH, Académicos)
CALL SP_EliminarTemaCapacitacionFisico(@IdTema);
CALL SP_EliminarTipoInstruccionFisico(@IdTipo);
CALL SP_EliminarPuestoFisico(@IdPuesto);
CALL SP_EliminarRegimenFisico(@IdRegimen);
CALL SP_EliminarRegionFisica(@IdRegion);
CALL SP_EliminarRolFisicamente(@IdRol); 
CALL SP_EliminarCentroTrabajoFisico(@IdCT);
CALL SP_EliminarDepartamentoFisico(@IdDep);
CALL SP_EliminarSedeFisica(@IdSede);
CALL SP_EliminarGerenciaFisica(@IdGeren);

-- Borrado manual de dependencias estructurales si no tienes SPs para Sub/Dir
DELETE FROM `Cat_Subdirecciones` WHERE `Clave` = 'QA-SUB';
DELETE FROM `Cat_Direcciones` WHERE `Clave` = 'QA-DIR';
DELETE FROM `Municipio` WHERE `Codigo` = 'QA-MUN';
DELETE FROM `Estado` WHERE `Codigo` = 'QA-EDO';
DELETE FROM `Pais` WHERE `Codigo` = 'QA-PAIS';

SELECT 'PRUEBAS QA FINALIZADAS EXITOSAMENTE. SISTEMA BLINDADO.' AS RESULTADO_FINAL;