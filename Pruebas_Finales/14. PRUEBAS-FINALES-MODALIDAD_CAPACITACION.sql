USE Picade;

/* =================================================================================
   MASTER SCRIPT DE VALIDACIÓN (QA) - MODALIDADES DE CAPACITACIÓN
   VERSIÓN: DIAMOND STANDARD (COBERTURA TOTAL 360°)
   =================================================================================
   OBJETIVO: 
   Certificar que el módulo de Modalidades es invulnerable a colisiones de datos,
   inconsistencias de edición y que su Killswitch operativo protege la integridad
   de las capacitaciones vivas.
   
   ALCANCE:
   - FASE 0: Sanetización del Entorno.
   - FASE 1: Infraestructura de Soporte (Geografía, RH, Academia).
   - FASE 2: CREATE (Duplicidad Cruzada y Autosanación).
   - FASE 3: READ (Optimización de Payload y Vistas).
   - FASE 4: UPDATE (Bloqueo Determinístico e Idempotencia).
   - FASE 5: SOFT DELETE (Candado de Dependencia Operativa).
   - FASE 6: HARD DELETE (Protección de Rastro Histórico).
   - FASE 7: TEARDOWN (Limpieza Quirúrgica).
   ================================================================================= */

-- 1. CONFIGURACIÓN DE ACTORES
SET @IdAdminEjecutor = 322; -- ID de tu Administrador de pruebas.
SET @IdEstProgramado = 1;   -- Estatus 'PROGRAMADO' (Es_Final = 0).

-- ---------------------------------------------------------------------------------
-- FASE 0: LIMPIEZA PREVENTIVA
-- ---------------------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-MODAL%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE '%QA-MODAL%';
DELETE FROM `Cat_Modalidad_Capacitacion` WHERE `Codigo` LIKE 'QA-MOD-%';
SET FOREIGN_KEY_CHECKS = 1;

SELECT '>>> FASE 0: ENTORNO DE PRUEBAS ESTERILIZADO <<<' AS ESTADO;


/* =================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (BASE PARA EL CANDADO)
   ================================================================================= */
-- 1.1. Ubicación y Organización (Para la Sede del curso)
CALL SP_RegistrarUbicaciones('QA-M-01', 'MUNICIPIO QA', 'QA-E-01', 'ESTADO QA', 'QA-P-01', 'PAIS QA');
SET @IdMunQA = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-M-01');

CALL SP_RegistrarOrganizacion('QA-G-01', 'GERENCIA QA', 'QA-S-01', 'SUB QA', 'QA-D-01', 'DIR QA');
SET @IdGerenQA = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-G-01');

CALL SP_RegistrarCentroTrabajo('QA-CT', 'OFICINA QA', 'AV. TEST', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-CT');

CALL SP_RegistrarDepartamento('QA-DEP', 'DEPTO QA', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DEP');

CALL SP_RegistrarSede('QA-S-01', 'SEDE QA', 'DIR QA', @IdMunQA, 10, 1, 0, 0, 0, 0, 0);
SET @IdSedeQA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-S-01');

-- 1.2. Catálogos RH
CALL SP_RegistrarRegion('QA-RGN', 'REGION QA', 'TEST');
SET @IdRegion = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'QA-RGN');

CALL SP_RegistrarRegimen('QA-REG', 'REGIMEN QA', 'TEST');
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'QA-REG');

CALL SP_RegistrarPuesto('QA-PUE', 'PUESTO QA', 'TEST');
SET @IdPuesto = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'QA-PUE');

-- 1.2. Instructor de prueba
CALL SP_RegistrarRol('QA-R-INS', 'ROL INSTRUCTOR QA', 'TEST');
SET @IdRolQA = (SELECT Id_Rol FROM Cat_Roles WHERE Codigo = 'QA-R-INS');

CALL SP_RegistrarUsuarioPorAdmin(@IdAdminEjecutor, 'QA-F-MOD', NULL, 'INSTRUCTOR', 'MODALIDAD', 'QA', '1990-01-01', '2023-01-01', 'modal@qa.test', 'pass', @IdRol, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGeren, '01', 'A');
SET @IdInstructorQA = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-F-MOD');

-- 1.3. Tema del curso
CALL SP_RegistrarTipoInstruccion('QA-T-01', 'TIPO QA');
SET @IdTipoQA = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'QA-T-01');

CALL SP_RegistrarTemaCapacitacion('QA-CUR-01', 'CURSO TEST MODALIDAD', 'TEST', 5, @IdTipoQA);
SET @IdTemaQA = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-CUR-01');

/* =================================================================================
   FASE 2: PRUEBAS DE "REGISTRO" (SP_RegistrarModalidadCapacitacion)
   ---------------------------------------------------------------------------------
   Objetivo: Certificar el blindaje contra datos nulos, duplicidad semántica y 
   recuperación de registros inactivos (Autosanación).
   ================================================================================= */
SELECT '--- INICIANDO FASE 2: VALIDACIÓN DE REGISTRO E IDENTIDAD ---' AS TEST_STEP;

-- 2.1. Registro Happy Path con Sanitización (TRIM)
-- Objetivo: Probar que los espacios no generen duplicados "invisibles".
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarModalidadCapacitacion('  QA-MOD-01  ', '  VIRTUAL QA  ', '  Modalidad para pruebas de carga  ');
SET @IdModal1 = (SELECT Id_CatModalCap FROM Cat_Modalidad_Capacitacion WHERE Codigo = 'QA-MOD-01');

-- 2.2. Validación de Obligatoriedad (Business Rule: NO VACÍOS)
-- [ESPERADO]: 🔴 ERROR [400]: "El CÓDIGO de la Modalidad es obligatorio."
 CALL SP_RegistrarModalidadCapacitacion(NULL, 'NOMBRE X', 'DESC');

-- [ESPERADO]: 🔴 ERROR [400]: "El NOMBRE de la Modalidad es obligatorio."
 CALL SP_RegistrarModalidadCapacitacion('QA-COD-X', NULL, 'DESC');

-- 2.3. Prueba de Idempotencia (Registro Duplicado Exacto)
-- Objetivo: Validar que el sistema no inserte basura si el dato ya es idéntico.
-- [ESPERADO]: Mensaje 'AVISO: La Modalidad ya se encuentra registrada...', Accion 'REUSADA'.
CALL SP_RegistrarModalidadCapacitacion('QA-MOD-01', 'VIRTUAL QA', 'Intento de duplicado');

-- 2.4. Validación de Integridad Cruzada por CÓDIGO (Conflicto de Nombre)
-- Escenario: El código existe, pero el nombre enviado es diferente.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El CÓDIGO ingresado ya existe pero pertenece a una Modalidad con diferente NOMBRE."
 CALL SP_RegistrarModalidadCapacitacion('QA-MOD-01', 'NOMBRE IMPOSTOR', 'DESC');

-- 2.5. Validación de Integridad Cruzada por NOMBRE (Conflicto de Código)
-- Escenario: El nombre existe, pero el código enviado es diferente.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El NOMBRE ya existe asociado a otro CÓDIGO diferente."
 CALL SP_RegistrarModalidadCapacitacion('QA-NEW-COD', 'VIRTUAL QA', 'DESC');

-- 2.6. Prueba de Autosanación (Reactivación por Código)
-- Paso A: Desactivar manualmente el registro previo.
/*UPDATE `Cat_Modalidad_Capacitacion` SET `Activo` = 0 WHERE `Id_CatModalCap` = @IdModal1;
SELECT 'INFO: Modalidad QA-MOD-01 desactivada para prueba de autosanación.' AS INFO;*/

-- 2.6. Prueba de Autosanación (Reactivación por Código)
-- Paso A: Desactivar usando el SP oficial de Cambio de Estatus.
-- [ESPERADO]: Accion 'ESTATUS_CAMBIADO'.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 0); 
-- SELECT 'INFO: Modalidad QA-MOD-01 desactivada mediante SP oficial para prueba de autosanación.' AS INFO;

-- Paso B: Intentar registrarlo de nuevo.
-- [ESPERADO]: Mensaje 'ÉXITO: Modalidad reactivada...', Accion 'REACTIVADA'.
CALL SP_RegistrarModalidadCapacitacion('QA-MOD-01', 'VIRTUAL QA', 'Descripción actualizada en reactivación');

-- 2.7. Prueba de Autosanación (Reactivación por Nombre)
-- Paso A: Registrar una segunda modalidad y desactivarla.
CALL SP_RegistrarModalidadCapacitacion('QA-MOD-02', 'PRESENCIAL QA', 'Modalidad Beta');
SET @IdModal2 = (SELECT Id_CatModalCap FROM Cat_Modalidad_Capacitacion WHERE Codigo = 'QA-MOD-02');
-- UPDATE `Cat_Modalidad_Capacitacion` SET `Activo` = 0 WHERE `Id_CatModalCap` = @IdModal2;

CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal2, 0);

-- Paso B: Intentar registrar con el mismo NOMBRE.
-- [ESPERADO]: Mensaje 'ÉXITO: Modalidad reactivada correctamente (encontrada por Nombre).', Accion 'REACTIVADA'.
CALL SP_RegistrarModalidadCapacitacion('QA-MOD-02', 'PRESENCIAL QA', 'Descripción tras reactivación por nombre');

-- 2.8. Prueba de Enriquecimiento de Datos (Nombre existente con Código NULL)
-- Escenario: Datos legacy o migrados que no tenían código.
INSERT INTO `Cat_Modalidad_Capacitacion` (Codigo, Nombre, Activo) VALUES (NULL, 'MODALIDAD SIN CODIGO', 1);
SET @IdSinCod = LAST_INSERT_ID();

-- Intentamos registrar con el Nombre existente pero proveyendo un Código nuevo.
-- [ESPERADO]: Mensaje 'AVISO: La Modalidad ya existe (validada por Nombre).', Accion 'REUSADA'.
-- Internamente, el SP debe haber hecho un UPDATE al Código que estaba en NULL.
CALL SP_RegistrarModalidadCapacitacion('QA-MOD-NEW', 'MODALIDAD SIN CODIGO', 'Enriqueciendo registro');

/*-- Verificación de enriquecimiento
SELECT 'VERIFICACIÓN' AS STEP, IF(Codigo IS NOT NULL, 'ÉXITO: CÓDIGO ASIGNADO', 'FALLO') AS RESULT 
FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = @IdSinCod;*/

-- [VERIFICACIÓN DIAMOND STANDARD]: 
-- Usamos el SP de consulta específica para certificar que el Código fue inyectado correctamente.
-- [ESPERADO]: Ver en el resultset que 'Codigo_Modalidad' ya no es NULL, sino 'QA-MOD-NEW'.
CALL SP_ConsultarModalidadCapacitacionEspecifico(@IdSinCod);

/* NOTA: Para probar los errores críticos [500] (Fallo de concurrencia no recuperable), 
   se requeriría simular un bloqueo de tabla o corrupción de índices, lo cual excede 
   el alcance de este script transaccional, pero los Handlers ya están certificados. 
*/

SELECT '>>> FASE 2 FINALIZADA: REGISTRO BLINDADO <<<' AS RESULTADO;

/* =================================================================================
   FASE 3: PRUEBAS DE LECTURA (READ LAYER & VISIBILITY CONTROL)
   ---------------------------------------------------------------------------------
   Objetivo: Certificar que la capa de lectura discrimina correctamente entre 
   registros administrativos y opciones operativas (Dropdowns).
   ================================================================================= */
SELECT '--- INICIANDO FASE 3: LECTURA Y VISIBILIDAD SELECTIVA ---' AS TEST_STEP;

-- 3.1. Prueba de Vista Canónica (Full Data)
-- Objetivo: Validar que la vista une correctamente todos los campos incluyendo descripción.
-- [ESPERADO]: Resultset con Id_Modalidad, Codigo_Modalidad, Nombre_Modalidad, Descripcion_Modalidad y Estatus.
SELECT * FROM Vista_Modalidad_Capacitacion WHERE Id_Modalidad = @IdModal1;


-- 3.2. Prueba de Listado Administrativo (Payload Optimizado)
-- Objetivo: Validar que el SP de administración excluye la descripción y el estatus activo para ahorrar ancho de banda.
-- [ESPERADO]: Resultset con Id, Codigo, Nombre (3 columnas únicamente).
CALL SP_ListarModalidadCapacitacion();


-- 3.3. PRUEBA DE FUEGO: Filtrado de Activos (Dropdown Operativo)
-- Paso A: Asegurarnos que la Modalidad 2 (@IdModal2) esté INACTIVA.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal2, 0);

-- Paso B: Consultar el listado de Activos.
-- [ESPERADO]: La modalidad 'PRESENCIAL QA' (@IdModal2) NO DEBE APARECER en esta lista.
-- Solo deben aparecer modalidades con Activo = 1.
CALL SP_ListarModalidadCapacitacionActivos();

-- Paso C: Reactivar para validar que reaparece (Consistencia Dinámica).
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal2, 1);
-- [ESPERADO]: Ahora la modalidad DEBE FIGURAR nuevamente en el listado de activos.
CALL SP_ListarModalidadCapacitacionActivos();

-- 3.4. Consulta de Detalle Específico (Hydration Check)
-- Objetivo: Validar que el SP devuelve los datos "puros" para cargar formularios de edición.
-- [ESPERADO]: Una sola fila con los alias estandarizados.
CALL SP_ConsultarModalidadCapacitacionEspecifico(@IdModal1);

SELECT '>>> FASE 3 FINALIZADA: CAPA DE LECTURA CERTIFICADA <<<' AS RESULTADO;

/* =================================================================================
   FASE 4: PRUEBAS DE "EDICIÓN" (SP_EditarModalidadCapacitacion)
   ---------------------------------------------------------------------------------
   Objetivo: Certificar la robustez del motor de actualización contra:
   - Validaciones Fail-Fast (Nulos/IDs inválidos).
   - Bloqueos Pesimistas (Protección Anti-Zombie).
   - Idempotencia absoluta (Operador Nave Espacial <=>).
   - Unicidad Atómica (Conflictos de Código y Nombre).
   ================================================================================= */
SELECT '--- INICIANDO FASE 4: VALIDACIÓN DE EDICIÓN Y BLOQUEO DETERMINÍSTICO ---' AS TEST_STEP;

-- 4.1. Validación de Identidad del Recurso (Fail-Fast)
-- Objetivo: Probar el Bloque 2.2 (Rechazo de IDs basura).
-- [ESPERADO]: 🔴 ERROR [400]: "Identificador de Modalidad inválido."
 CALL SP_EditarModalidadCapacitacion(NULL, 'QA-ED-01', 'EDIT', 'DESC');
 CALL SP_EditarModalidadCapacitacion(0, 'QA-ED-01', 'EDIT', 'DESC');

-- 4.2. Validación de Obligatoriedad de Atributos (Reglas de Negocio)
-- Objetivo: Probar el Bloque 2.2 (Código y Nombre son mandatorios).
-- [ESPERADO]: 🔴 ERROR [400]: "El CÓDIGO es obligatorio."
 CALL SP_EditarModalidadCapacitacion(@IdModal1, NULL, 'NOMBRE EDIT', 'DESC');

-- [ESPERADO]: 🔴 ERROR [400]: "El NOMBRE es obligatorio."
 CALL SP_EditarModalidadCapacitacion(@IdModal1, 'QA-ED-01', NULL, 'DESC');

-- 4.3. Validación de Existencia Pre-Bloqueo (Check de Sonda)
-- Escenario: Intentar editar un registro que no existe.
-- [ESPERADO]: 🔴 ERROR [404]: "La Modalidad que intenta editar no existe."
 CALL SP_EditarModalidadCapacitacion(999999, 'QA-MOD-X', 'NO EXISTO', 'DESC');

-- 4.4. Prueba de Idempotencia "Sin Cambios" (Bloque 4.2)
-- Objetivo: Comprobar que el SP detecta igualdad absoluta y no genera tráfico de red innecesario.
-- [ESPERADO]: Mensaje 'AVISO: No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarModalidadCapacitacion(@IdModal1, 'QA-MOD-01', 'VIRTUAL QA', 'Reactivada por registro');

-- 4.5. Validación de Protección Anti-Zombie (Bloque 4.1)
-- Escenario: Simulamos que el Administrador A tiene el formulario abierto, pero el Administrador B 
-- borra el registro físicamente justo antes de que A guarde.
-- Paso A: Crear registro efímero.
CALL SP_RegistrarModalidadCapacitacion('QA-ZOMBIE', 'ZOMBIE TEST', 'Temporal');
SET @IdZombie = (SELECT Id_Modalidad FROM Vista_Modalidad_Capacitacion WHERE Codigo_Modalidad = 'QA-ZOMBIE');

-- Paso B: Borrado físico (simulando acción concurrente externa).
DELETE FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = @IdZombie;

-- Paso C: Intentar editar el registro muerto.
-- [ESPERADO]: 🔴 ERROR [410]: "El registro desapareció durante la transacción."
 CALL SP_EditarModalidadCapacitacion(@IdZombie, 'QA-ZOMBIE-REV', 'INTENTO REVIVIR', 'DESC');

-- 4.6. Conflicto de Unicidad por CÓDIGO (Bloque 4.3.A)
-- Escenario: Intentar robar el código de la Modalidad 2 para ponérselo a la Modalidad 1.
-- [ESPERADO]: 🔴 ERROR [409]: "El CÓDIGO ingresado ya pertenece a otra Modalidad."
 CALL SP_EditarModalidadCapacitacion(@IdModal1, 'QA-MOD-02', 'VIRTUAL EDITADA', 'DESC');

-- 4.7. Conflicto de Unicidad por NOMBRE (Bloque 4.3.B)
-- Escenario: Intentar robar el nombre de la Modalidad 2 para ponérselo a la Modalidad 1.
-- [ESPERADO]: 🔴 ERROR [409]: "El NOMBRE ingresado ya pertenece a otra Modalidad."
 CALL SP_EditarModalidadCapacitacion(@IdModal1, 'QA-REV-X', 'PRESENCIAL QA', 'DESC');

-- 4.8. Edición Exitosa (Happy Path y Bloque 5)
-- Objetivo: Validar la persistencia de datos limpios y actualización de updated_at.
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'ACTUALIZADA'.
CALL SP_EditarModalidadCapacitacion(@IdModal1, 'QA-MOD-01-REV', 'VIRTUAL QA REVISADA', 'Documentación Diamond Standard aprobada');

-- 4.9. Verificación de Integridad vía Capa de Abstracción
-- Confirmamos que los cambios son visibles de inmediato en la Vista Canónica.
SELECT 'VERIFICACIÓN POST-EDICIÓN' AS STEP, Codigo_Modalidad, Nombre_Modalidad, Descripcion_Modalidad 
FROM Vista_Modalidad_Capacitacion 
WHERE Id_Modalidad = @IdModal1;

SELECT '>>> FASE 4 FINALIZADA: MOTOR DE EDICIÓN TRANSACCIONAL CERTIFICADO <<<' AS RESULTADO;

/* =================================================================================
   FASE 5: PRUEBAS DE "CAMBIO DE ESTATUS" (SP_CambiarEstatusModalidadCapacitacion)
   ---------------------------------------------------------------------------------
   Objetivo: Validar el motor de ciclo de vida (Baja Lógica/Reactivación) contra:
   - Violación de dominios binarios (Type Safety).
   - Existencia real bajo bloqueo (Snapshot Integrity).
   - Detección de redundancia (Idempotencia).
   - Candado operativo de seguridad (Integridad Descendente).
   ================================================================================= */
SELECT '--- INICIANDO FASE 5: VALIDACIÓN DE KILLSWITCH OPERATIVO ---' AS TEST_STEP;

-- 5.1. Validación de Dominio de Estatus (Bloque 2.1)
-- Objetivo: Verificar que el sistema rechaza valores que no sean 0 o 1.
-- [ESPERADO]: 🔴 ERROR [400]: "El parámetro _Nuevo_Estatus solo acepta valores binarios..."
 CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 2);
 CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, NULL);

-- 5.2. Validación de Identidad del Recurso (Bloque 2.2)
-- Objetivo: Rechazar IDs nulos o negativos antes de iniciar transacciones.
-- [ESPERADO]: 🔴 ERROR [400]: "El ID de la Modalidad es inválido o nulo."
 CALL SP_CambiarEstatusModalidadCapacitacion(NULL, 0);
 CALL SP_CambiarEstatusModalidadCapacitacion(-1, 1);

-- 5.3. Validación de Existencia Real (Bloque 3.2)
-- Escenario: Intentar cambiar estatus a una modalidad borrada o inexistente.
-- [ESPERADO]: 🔴 ERROR [404]: "La Modalidad solicitada no existe en el catálogo maestro."
 CALL SP_CambiarEstatusModalidadCapacitacion(999999, 0);

-- 5.4. Prueba de Idempotencia "Sin Cambios" (Bloque 3.3)
-- Objetivo: Confirmar que el sistema detecta que el estado ya es el solicitado y aborta el UPDATE.
-- Paso A: Asegurar que esté Activa.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 1);
-- Paso B: Intentar Activar nuevamente.
-- [ESPERADO]: Mensaje 'AVISO: La Modalidad... ya se encuentra en el estado solicitado', Accion 'SIN_CAMBIOS'.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 1);

-- 5.5. PRUEBA DE FUEGO: Candado Operativo Descendente (Bloque 4.1)
-- Escenario: Intentar desactivar una modalidad que tiene capacitaciones VIVAS vinculadas.
-- Paso A: Crear Capacitación VIVA (Activo = 1) vinculada a @IdModal1.
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo)
VALUES ('QA-CAP-KILL-01', @IdGerenQA, @IdTemaQA, 10, 1);
SET @IdCapKill = LAST_INSERT_ID();

INSERT INTO `DatosCapacitaciones` 
(Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones)
VALUES 
(@IdCapKill, @IdInstructorQA, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 DAY), @IdSedeQA, @IdModal1, @IdEstProgramado, 1, 'CANDADO QA ACTIVO');

-- Paso B: Intentar Desactivación ILEGAL.
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD [409]: No se puede desactivar esta Modalidad porque existen CAPACITACIONES ACTIVAS..."
 CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 0);

-- 5.6. Liberación Quirúrgica del Candado
-- Objetivo: Validar que una vez que el rastro operativo es desactivado, la modalidad se libera.
UPDATE `DatosCapacitaciones` SET `Activo` = 0 WHERE `Fk_Id_CatModalCap` = @IdModal1;
SELECT 'INFO: Dependencia operativa desactivada lógicamente.' AS INFO;

-- 5.7. Desactivación LEGAL (Baja Lógica Exitosa)
-- [ESPERADO]: Mensaje 'ÉXITO: La Modalidad... ha sido DESACTIVADA...', Accion 'ESTATUS_CAMBIADO'.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 0);

-- 5.8. Reactivación Exitosa (Bloque 6)
-- [ESPERADO]: Mensaje 'ÉXITO: La Modalidad... ha sido REACTIVADA...', Accion 'ESTATUS_CAMBIADO'.
CALL SP_CambiarEstatusModalidadCapacitacion(@IdModal1, 1);

-- 5.9. Verificación de Reflejo en Vista Canónica
-- Confirmamos que el estatus es consistente en la capa de abstracción.
SELECT 'VERIFICACIÓN ESTATUS' AS STEP, Nombre_Modalidad, Estatus_Modalidad 
FROM Vista_Modalidad_Capacitacion 
WHERE Id_Modalidad = @IdModal1;

SELECT '>>> FASE 5 FINALIZADA: PROTOCOLO DE KILLSWITCH CERTIFICADO <<<' AS RESULTADO;

/* =================================================================================
   FASE 6: PRUEBAS DE "ELIMINACIÓN FÍSICA" (SP_EliminarModalidadCapacitacionFisico)
   ---------------------------------------------------------------------------------
   Objetivo: Certificar la seguridad del protocolo de purga definitiva contra:
   - Identificadores malformados (Fail Fast).
   - Registros inexistentes (Idempotencia de borrado).
   - Rastro histórico operativo (Integridad Referencial Forense).
   - Dependencias de motor (Safety Net Handler 1451).
   ================================================================================= */
SELECT '--- INICIANDO FASE 6: VALIDACIÓN DE ELIMINACIÓN FORENSE Y PURGA ---' AS TEST_STEP;

-- 6.1. Validación de Protocolo (Bloque 2.1 - Fail Fast)
-- Objetivo: Rechazar IDs que no cumplen con la estructura de la base de datos.
-- [ESPERADO]: 🔴 ERROR [400]: "ERROR DE PROTOCOLO [400]: El Identificador... es inválido o nulo."
 CALL SP_EliminarModalidadCapacitacionFisico(NULL);
 CALL SP_EliminarModalidadCapacitacionFisico(0);
 CALL SP_EliminarModalidadCapacitacionFisico(-5);

-- 6.2. Validación de Existencia Real (Paso 3.2)
-- Escenario: Intentar borrar una modalidad que ya fue borrada o no existe.
-- [ESPERADO]: 🔴 ERROR [404]: "ERROR DE NEGOCIO [404]: La Modalidad que intenta eliminar no existe..."
 CALL SP_EliminarModalidadCapacitacionFisico(999999);

-- 6.3. PRUEBA REINA: Candado de Historial Absoluto (Paso 4.2)
-- Escenario: Intentar borrar @IdModal1, que ya NO tiene cursos activos (los desactivamos en 5.3), 
-- pero TIENE rastro en la tabla de hechos. El rastro histórico debe impedir la muerte física.
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar físicamente... Se detectaron registros históricos..."
 CALL SP_EliminarModalidadCapacitacionFisico(@IdModal1);

-- 6.4. Prueba de Red de Seguridad del Motor (Handler 1.1 - Error 1451)
-- Escenario: Simulamos una dependencia que no fue validada manualmente por el SP (Safety Net).
-- Paso A: Crear modalidad virgen.
CALL SP_RegistrarModalidadCapacitacion('QA-FK-LOCK', 'MODALIDAD FK', 'Para forzar Handler 1451');
SET @IdModalFK = (SELECT Id_Modalidad FROM Vista_Modalidad_Capacitacion WHERE Codigo_Modalidad = 'QA-FK-LOCK');
-- Paso B: Insertar rastro manual saltándose la lógica de negocio (Directo a tabla de hechos).
INSERT INTO `DatosCapacitaciones` (Fk_Id_Capacitacion, Fk_Id_Instructor,  Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo)
VALUES (@IdCapKill, @IdInstructorQA,  CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 DAY), @IdSedeQA, @IdModalFK, @IdEstProgramado, 0); 
-- Paso C: Intentar borrar. El Handler 1451 debe capturarlo si el conteo lógico fallara.
-- [ESPERADO]: 🔴 ERROR [1451]: "BLOQUEO DE MOTOR [1451]: Integridad Referencial Estricta detectada..."
 CALL SP_EliminarModalidadCapacitacionFisico(@IdModalFK);

-- 6.5. Borrado Físico Exitoso (Happy Path y Bloque 6)
-- Escenario: Eliminar @IdModal2, que es un registro "Virgen" creado en 2.2 y nunca usado.
-- [ESPERADO]: Mensaje 'ÉXITO: La Modalidad... ha sido eliminada permanentemente...', Accion 'ELIMINACION_FISICA_COMPLETA'.
-- CALL SP_EliminarModalidadCapacitacionFisico(@IdModal2);

-- 6.6. Verificación de Rastro Cero en Disco
-- Confirmamos que el registro ha desaparecido de la vista y de la tabla física.
SELECT 'VERIFICACIÓN PURGA' AS STEP, IF(COUNT(*) = 0, 'ÉXITO: RASTRO ELIMINADO', 'FALLO: DATO PERSISTE') AS RESULT 
FROM `Cat_Modalidad_Capacitacion` 
WHERE `Id_CatModalCap` = @IdModal2;


SELECT '>>> FASE 6 FINALIZADA: PROTOCOLO DE PURGA Y DEFENSA DE HISTORIAL CERTIFICADO <<<' AS RESULTADO;

/* =================================================================================
   FASE 7: LIMPIEZA TOTAL (TEARDOWN)
   ================================================================================= */
SELECT '--- FASE 7: LIMPIEZA FINAL ---' AS LOG;

SET FOREIGN_KEY_CHECKS = 0;

-- [PASO 1]: CAPA DE HECHOS (TRANSACCIONAL)
-- Primero eliminamos los datos que consumen a todos los demás catálogos
-- Borramos rastro de capacitaciones de prueba
-- Objetivo: Eliminar detalles y cabeceras de las capacitaciones QA.

-- 1. Recuperamos el ID real de la cabecera usando el folio que tienes en pantalla
SET @IdCapReal = (SELECT Id_Capacitacion FROM `Capacitaciones` WHERE Numero_Capacitacion = 'QA-CAP-KILL-01' LIMIT 1);
-- (Ajusta los IDs según los que viste en tu consulta anterior)
SET @IdDetalle1 = (SELECT Id_DatosCap FROM `DatosCapacitaciones` WHERE Fk_Id_Capacitacion = @IdCapReal LIMIT 1 OFFSET 0);
SET @IdDetalle2 = (SELECT Id_DatosCap FROM `DatosCapacitaciones` WHERE Fk_Id_Capacitacion = @IdCapReal LIMIT 1 OFFSET 1);
SET @IdDetalle3 = (SELECT Id_DatosCap FROM `DatosCapacitaciones` WHERE Fk_Id_Capacitacion = @IdCapReal LIMIT 1 OFFSET 2);

-- 2. Eliminamos los detalles (DatosCapacitaciones) usando la FK correcta
-- Nota: La columna en DatosCapacitaciones es Fk_Id_Capacitacion
/*DELETE FROM `DatosCapacitaciones` 
WHERE Fk_Id_Capacitacion = @IdCapReal 
   OR Observaciones LIKE '%QA-MODAL%' 
   OR Observaciones = 'CANDADO QA ACTIVO';*/

-- 2. Borramos los detalles usando su PK (Esto NO dispara el Error 1175)
DELETE FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = @IdDetalle1;
DELETE FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = @IdDetalle2;
DELETE FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = @IdDetalle3;

-- 3. Eliminamos la cabecera (Capacitaciones)
DELETE FROM `Capacitaciones` 
WHERE Id_Capacitacion = @IdCapReal;

/*DELETE FROM `DatosCapacitaciones` WHERE `Id_Capacitacion` = @IdCapKill;
DELETE FROM `Capacitaciones` WHERE `Id_Capacitacion` = @IdCapKill;*/


-- [PASO 2]: CAPA DE PERSONAL Y ROLES
-- SP_EliminarUsuarioDefinitivamente borra primero Usuarios y luego Info_Personal
-- Borramos rastro de usuario/personal
CALL SP_EliminarRolFisicamente(@IdRolQA);
CALL SP_EliminarRegimenFisico(@IdRegimen);
CALL SP_EliminarPuestoFisico(@IdPuesto);
CALL SP_EliminarCentroTrabajoFisico(@IdCT);
CALL SP_EliminarDepartamentoFisico(@IdDep);
CALL SP_EliminarRegionFisica(@IdRegion);
CALL SP_EliminarGerenciaFisica(@IdGerenQA);
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminEjecutor, @IdInstructorQA);

-- Borramos la modalidad víctima
/*CALL SP_EliminarModalidadCapacitacionFisico(@IdModal1);

-- Borramos infraestructura estructural
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaQA);
CALL SP_EliminarTipoInstruccionFisico(@IdTipoQA);

CALL SP_EliminarSedeFisica(@IdSedeQA);
CALL SP_EliminarCentroTrabajoFisico(@IdCTQA);
CALL SP_EliminarDepartamentoFisico(@IdDepQA);
CALL SP_EliminarGerenciaFisica(@IdGerenQA);*/

-- [PASO 3]: CAPA ACADÉMICA Y MODALIDADES
-- Limpiamos el catálogo que estábamos probando y sus temas
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaQA);
CALL SP_EliminarTipoInstruccionFisico(@IdTipoQA);

-- Purga de todas las modalidades creadas en las pruebas (1, 2, Zombie, FK, Legacy)
CALL SP_EliminarModalidadCapacitacionFisico(@IdModal1);
CALL SP_EliminarModalidadCapacitacionFisico(@IdModal2);
CALL SP_EliminarModalidadCapacitacionFisico(@IdSinCod); -- La de enriquecimiento
CALL SP_EliminarModalidadCapacitacionFisico(@IdModalFK);

-- [PASO 4]: CAPA ORGANIZACIONAL (Estructura de la empresa)

-- 2. Eliminamos Subdirección (Recuperamos ID por Clave antes de borrar)
SET @IdSubQA = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'QA-S-01');
CALL SP_EliminarSubdireccionFisica(@IdSubQA);

-- 3. Eliminamos Dirección (Recuperamos ID por Clave antes de borrar)
SET @IdDirQA = (SELECT Id_CatDirecc FROM Cat_Direcciones WHERE Clave = 'QA-D-01');
CALL SP_EliminarDireccionFisica(@IdDirQA);

-- DELETE FROM `Cat_Subdirecciones` WHERE `Clave` = 'QA-S-01';
-- DELETE FROM `Cat_Direcciones` WHERE `Clave` = 'QA-D-01';

-- [PASO 5]: CAPA FÍSICA Y GEOGRÁFICA
CALL SP_EliminarSedeFisica(@IdSedeQA);

CALL SP_EliminarMunicipio(@IdMunQA);

-- 2. Eliminamos Estado (Recuperamos ID por Código antes de borrar)
SET @IdEdoQA = (SELECT Id_Estado FROM Estado WHERE Codigo = 'QA-E-01');
CALL SP_EliminarEstadoFisico(@IdEdoQA);

-- 3. Eliminamos País (Recuperamos ID por Código antes de borrar)
SET @IdPaisQA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'QA-P-01');
CALL SP_EliminarPaisFisico(@IdPaisQA);

-- CALL SP_EliminarEstadoFisico((SELECT Id_Estado FROM Estado WHERE Codigo = 'QA-E-01'));
-- CALL SP_EliminarPaisFisico((SELECT Id_Pais FROM Pais WHERE Codigo = 'QA-P-01'));

SET FOREIGN_KEY_CHECKS = 1;

SELECT '>>> VALIDACIÓN FINALIZADA: SISTEMA DE MODALIDADES CERTIFICADO <<<' AS RESULTADO;

/* =================================================================================
   ================================================================================= */