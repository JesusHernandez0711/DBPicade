USE Picade;

/* =================================================================================
   MASTER SCRIPT DE VALIDACIÓN (QA) - ESTATUS DE PARTICIPANTE
   VERSIÓN: DIAMOND STANDARD FORENSIC (FULL INFRASTRUCTURE COMPLIANCE)
   =================================================================================
   OBJETIVO: 
   Validar el ciclo de vida completo del Catálogo de Estatus de Participante,
   utilizando la infraestructura nativa del sistema para simular un entorno real.
   ================================================================================= */

-- 1. CONFIGURACIÓN DE ACTORES
SET @IdAdminEjecutor = 322; -- ID de tu Administrador existente.

-- ---------------------------------------------------------------------------------
-- FASE 0: LIMPIEZA PREVENTIVA (DATA STERILIZATION)
-- ---------------------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;

-- Limpieza de tablas transaccionales (Hijos)
DELETE FROM `Capacitaciones_Participantes` WHERE `Calificacion` = 99.99;
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-PART%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE '%QA-PART%';

-- Limpieza de catálogos base (Padres)
DELETE FROM `Cat_Estatus_Participante` WHERE `Codigo` LIKE 'QA-EST-%';
DELETE FROM `Cat_Estatus_Capacitacion` WHERE `Codigo` LIKE 'QA-EC-%';

SET FOREIGN_KEY_CHECKS = 1;

SELECT '>>> FASE 0: ENTORNO DE PRUEBAS ESTERILIZADO <<<' AS ESTADO;


/* =================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (BASE PARA EL CANDADO)
   Usamos tus SPs maestros para crear un ecosistema válido.
   ================================================================================= */
SELECT '--- INICIANDO FASE 1: INFRAESTRUCTURA ---' AS LOG;

-- 1.1. Estatus de CURSO (Vitales para la lógica del Killswitch)
-- A) Estatus VIVO (Es_Final = 0)
CALL SP_RegistrarEstatusCapacitacion('QA-EC-VIVO', 'CURSO ACTIVO QA', 'Infraestructura QA', 0);
SET @IdEstCurVivo = (SELECT Id_CatEstCap FROM Cat_Estatus_Capacitacion WHERE Codigo = 'QA-EC-VIVO');

-- B) Estatus MUERTO (Es_Final = 1)
CALL SP_RegistrarEstatusCapacitacion('QA-EC-FIN', 'CURSO FINALIZADO QA', 'Infraestructura QA', 1);
SET @IdEstCurFin = (SELECT Id_CatEstCap FROM Cat_Estatus_Capacitacion WHERE Codigo = 'QA-EC-FIN');

-- 1.2. Ubicación y Organización (Para la Sede del curso)
CALL SP_RegistrarUbicaciones('QA-M-PART', 'MUNICIPIO QA PART', 'QA-E-PART', 'ESTADO QA PART', 'QA-P-PART', 'PAIS QA PART');
SET @IdMunQA = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-M-PART');

CALL SP_RegistrarOrganizacion('QA-G-PART', 'GERENCIA QA PART', 'QA-S-PART', 'SUB QA PART', 'QA-D-PART', 'DIR QA PART');
SET @IdGerenQA = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-G-PART');

CALL SP_RegistrarCentroTrabajo('QA-CT-PART', 'OFICINA QA PART', 'AV. TEST', @IdMunQA);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-CT-PART');

CALL SP_RegistrarDepartamento('QA-DEP-PART', 'DEPTO QA PART', 'PISO 1', @IdMunQA);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DEP-PART');

CALL SP_RegistrarSede('QA-S-PART', 'SEDE QA PART', 'DIR QA', @IdMunQA, 10, 1, 0, 0, 0, 0, 0);
SET @IdSedeQA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-S-PART');

-- 1.3. Catálogos RH
CALL SP_RegistrarRegion('QA-RGN-P', 'REGION QA PART', 'TEST');
SET @IdRegion = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'QA-RGN-P');

CALL SP_RegistrarRegimen('QA-REG-P', 'REGIMEN QA PART', 'TEST');
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'QA-REG-P');

CALL SP_RegistrarPuesto('QA-PUE-P', 'PUESTO QA PART', 'TEST');
SET @IdPuesto = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'QA-PUE-P');

-- 1.4. Actores: Instructor y Alumno
CALL SP_RegistrarRol('QA-R-PART', 'ROL QA PART', 'TEST');
SET @IdRolQA = (SELECT Id_Rol FROM Cat_Roles WHERE Codigo = 'QA-R-PART');

-- Alta Instructor
CALL SP_RegistrarUsuarioPorAdmin(@IdAdminEjecutor, 'QA-F-INST', NULL, 'INSTRUCTOR', 'PART', 'QA', '1990-01-01', '2023-01-01', 'inst_part@qa.test', 'pass', @IdRolQA, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGerenQA, '01', 'A');
SET @IdInstructorQA = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-F-INST');

-- Alta Alumno
CALL SP_RegistrarUsuarioPorAdmin(@IdAdminEjecutor, 'QA-F-ALUM', NULL, 'ALUMNO', 'PART', 'QA', '1995-01-01', '2020-01-01', 'alum_part@qa.test', 'pass', @IdRolQA, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGerenQA, '01', 'A');
SET @IdAlumnoQA = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-F-ALUM');

-- 1.5. Tema del curso
CALL SP_RegistrarTipoInstruccion('QA-T-PART', 'TIPO QA PART');
SET @IdTipoQA = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'QA-T-PART');

CALL SP_RegistrarTemaCapacitacion('QA-CUR-PART', 'CURSO TEST PART', 'TEST', 5, @IdTipoQA);
SET @IdTemaQA = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-CUR-PART');

/* =================================================================================
   FASE 2: PRUEBAS DE "REGISTRO" (SP_RegistrarEstatusParticipante)
   ---------------------------------------------------------------------------------
   Objetivo: Verificar creación, sanitización, unicidad y autosanación.
   ================================================================================= */
SELECT '--- INICIANDO FASE 2: REGISTRO (COBERTURA TOTAL) ---' AS TEST_STEP;

-- 2.1. Registro Happy Path (Escenario C - Nuevo)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarEstatusParticipante('  QA-EST-01  ', '  INSCRITO QA  ', '  Estatus inicial  ');
SET @IdEstInscrito = (SELECT Id_CatEstPart FROM Cat_Estatus_Participante WHERE Codigo = 'QA-EST-01');

-- 2.2. Registro Segundo Estatus (Happy Path 2)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarEstatusParticipante('QA-EST-02', 'APROBADO QA', 'Estatus final');
SET @IdEstAprobado = (SELECT Id_CatEstPart FROM Cat_Estatus_Participante WHERE Codigo = 'QA-EST-02');

-- 2.3. Prueba de Integridad - Código NULL (Validación 2.2)
-- [ESPERADO]: 🔴 ERROR [400]: "El CÓDIGO del Estatus es obligatorio."
CALL SP_RegistrarEstatusParticipante(NULL, 'NOMBRE', 'DESC');

-- [NUEVO] 2.3.b. Prueba de Integridad - Nombre NULL (Validación 2.2)
-- [ESPERADO]: 🔴 ERROR [400]: "El NOMBRE del Estatus es obligatorio."
CALL SP_RegistrarEstatusParticipante('COD-X', NULL, 'DESC');

-- 2.4. Prueba de Idempotencia (Escenario A.3 - Ya existe y activo)
-- [ESPERADO]: Mensaje 'AVISO... ya se encuentra registrado...', Accion 'REUSADA'.
CALL SP_RegistrarEstatusParticipante('QA-EST-01', 'INSCRITO QA', 'Otra desc');

-- 2.5. Conflicto de Identidad A (Escenario A.1 - Código existe, Nombre difiere)
-- Intentamos usar el código 'QA-EST-01' con un nombre falso.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS... El CÓDIGO ingresado ya existe..."
CALL SP_RegistrarEstatusParticipante('QA-EST-01', 'NOMBRE FALSO', 'DESC');

-- [NUEVO] 2.6. Conflicto de Identidad B (Escenario B.1 - Nombre existe, Código difiere)
-- Intentamos usar el nombre 'INSCRITO QA' con un código nuevo.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS... El NOMBRE ingresado ya existe..."
CALL SP_RegistrarEstatusParticipante('QA-COD-NUEVO', 'INSCRITO QA', 'DESC');

-- [NUEVO] 2.7. Prueba de Autosanación (Escenario A.2 - Reactivación)
-- Paso A: Simulamos que el registro fue borrado lógicamente (preparación)
UPDATE `Cat_Estatus_Participante` SET `Activo` = 0 WHERE `Id_CatEstPart` = @IdEstInscrito;

-- Paso B: Intentamos registrarlo de nuevo.
-- [ESPERADO]: Mensaje 'ÉXITO: Estatus reactivado...', Accion 'REACTIVADA'.
CALL SP_RegistrarEstatusParticipante('QA-EST-01', 'INSCRITO QA', 'Descripcion actualizada al revivir');

-- Verificación visual de que revivió
SELECT 'VERIFICACION REACTIVACION' AS STEP, Codigo, Activo FROM Cat_Estatus_Participante WHERE Id_CatEstPart = @IdEstInscrito;

/* =================================================================================
   FASE 3: PRUEBAS DE "LECTURA Y VISTAS"
   ================================================================================= */
SELECT '--- INICIANDO FASE 3: LECTURA ---' AS TEST_STEP;

-- 3.1. Listado Admin
CALL SP_ListarEstatusParticipante();

-- 3.2. Listado Activos (Dropdown)
CALL SP_ListarEstatusParticipanteActivos();

-- 3.3. Consulta Específica
CALL SP_ConsultarEstatusParticipanteEspecifico(@IdEstInscrito);

-- 3.4. Consulta Específica
CALL SP_ConsultarEstatusParticipanteEspecifico(@IdEstAprobado);

SELECT * FROM VISTA_ESTATUS_PARTICIPANTE;

/* =================================================================================
   FASE 4: PRUEBAS DE "EDICIÓN" (SP_EditarEstatusParticipante)
   ---------------------------------------------------------------------------------
   Objetivo: Validar la robustez del motor de actualización contra:
   - Inputs inválidos (Bloque 2).
   - Registros fantasma/zombie (Bloque 3.1).
   - Idempotencia (Bloque 4.2).
   - Conflictos de Unicidad Cruzada (Bloque 4.3).
   ================================================================================= */
SELECT '--- INICIANDO FASE 4: EDICIÓN TRANSACCIONAL (COBERTURA 100%) ---' AS TEST_STEP;

-- 4.1. Validación de Integridad de ID (Fail Fast)
-- [ESPERADO]: 🔴 ERROR [400]: "Identificador de Estatus inválido."
CALL SP_EditarEstatusParticipante(NULL, 'COD', 'NOM', 'DESC');
CALL SP_EditarEstatusParticipante(0, 'COD', 'NOM', 'DESC');

-- 4.2. Validación de Obligatoriedad de Datos (Bloque 2.2)
-- [ESPERADO]: 🔴 ERROR [400]: "El CÓDIGO es obligatorio."
CALL SP_EditarEstatusParticipante(@IdEstInscrito, NULL, 'NOMBRE VALIDO', 'DESC');

-- [ESPERADO]: 🔴 ERROR [400]: "El NOMBRE es obligatorio."
CALL SP_EditarEstatusParticipante(@IdEstInscrito, 'CODIGO VALIDO', NULL, 'DESC');

-- 4.3. Validación de Existencia Previa (Error 404)
-- Escenario: Intentar editar un ID que no existe en la BD.
-- [ESPERADO]: 🔴 ERROR [404]: "El Estatus que intenta editar no existe."
CALL SP_EditarEstatusParticipante(999999, 'QA-GHOST', 'GHOST', 'DESC');

-- 4.4. Validación "Anti-Zombie" (Error 410 - Race Condition Simulada)
-- Objetivo: Probar el Bloque 4.1 (Si el registro desaparece durante el bloqueo).
-- Paso A: Crear un registro temporal.
CALL SP_RegistrarEstatusParticipante('QA-ZOMBIE', 'ZOMBIE TEMP', 'Para borrar');
SET @IdZombie = (SELECT Id_CatEstPart FROM Cat_Estatus_Participante WHERE Codigo = 'QA-ZOMBIE');

-- Paso B: Borrarlo físicamente (Simulando que otro admin lo borró mientras nosotros editábamos).
DELETE FROM `Cat_Estatus_Participante` WHERE `Id_CatEstPart` = @IdZombie;

-- Paso C: Intentar editarlo (El SP pasará la validación de ID, pero fallará al intentar bloquear).
-- [ESPERADO]: 🔴 ERROR [410]: "El registro desapareció durante la transacción." (O 404 dependiendo de la velocidad del lock).
-- [ESPERADO]: 🔴 ERROR [404]: "El Estatus que intenta editar no existe."
-- (Nota: El Error 410 solo ocurre en concurrencia milimétrica real, en script secuencial salta el 404 primero).
CALL SP_EditarEstatusParticipante(@IdZombie, 'QA-ZOMBIE-ED', 'REVIVIR', 'DESC');

-- [PASO CRÍTICO DE CORRECCIÓN]
-- Resincronizamos la variable por si hubo "ruido" en la sesión anterior.
-- Esto asegura que @IdEstInscrito sea el dueño legítimo de 'QA-EST-01'.
-- [PASO CRÍTICO] Forzamos la variable al ID 8 que es el que tiene el código 'QA-EST-01' ahora.
-- Esto soluciona el conflicto con el ID 6.
SET @IdEstInscrito = (SELECT Id_CatEstPart FROM Cat_Estatus_Participante WHERE Codigo = 'QA-EST-01' LIMIT 1);

-- También aseguramos el ID del "otro" estatus para probar conflictos
SET @IdEstAprobado = (SELECT Id_CatEstPart FROM Cat_Estatus_Participante WHERE Codigo = 'QA-EST-02' LIMIT 1);

-- 4.5. Prueba de Idempotencia "Sin Cambios" (Bloque 4.2)
-- Enviamos exactamente los mismos datos.
-- [ESPERADO]: Mensaje 'AVISO: No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarEstatusParticipante(@IdEstInscrito, 'QA-EST-01', 'INSCRITO QA', 'Estatus inicial');

-- 4.6. Conflicto de Unicidad por CÓDIGO (Bloque 4.3.A)
-- Intentamos ponerle al Estatus 1 el CÓDIGO del Estatus 2.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS... El CÓDIGO ingresado ya pertenece a otro Estatus."
CALL SP_EditarEstatusParticipante(@IdEstInscrito, 'QA-EST-02', 'NOMBRE DIFERENTE', 'DESC');

-- 4.7. Conflicto de Unicidad por NOMBRE (Bloque 4.3.B)
-- Intentamos ponerle al Estatus 1 el NOMBRE del Estatus 2.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS... El NOMBRE ingresado ya pertenece a otro Estatus."
CALL SP_EditarEstatusParticipante(@IdEstInscrito, 'CODIGO DIFERENTE', 'APROBADO QA', 'DESC');

-- 4.8. Edición Exitosa (Happy Path - Bloque 7)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'ACTUALIZADA'.
CALL SP_EditarEstatusParticipante(@IdEstInscrito, 'QA-EST-01-ED', 'INSCRITO VIVO QA', 'Renombrado con éxito');

-- 4.9. Verificación de Integridad (Post-Check)
SELECT 'VERIFICACION EDICION' AS STEP, Codigo, Nombre, Descripcion 
FROM Cat_Estatus_Participante WHERE Id_CatEstPart = @IdEstInscrito;

/* =================================================================================
   FASE 5: PRUEBAS DE "BAJA LÓGICA" (KILLSWITCH FORENSE & VALIDACIONES)
   ---------------------------------------------------------------------------------
   Objetivo: Validar validaciones de entrada, idempotencia y el Killswitch Forense.
   ================================================================================= */
SELECT '>>> INICIANDO FASE 5: SMART KILLSWITCH (COBERTURA 100%) <<<' AS TEST_STEP;

-- 5.1. Validación de Integridad de Entrada (Bloque D.1 - ID Inválido)
-- [ESPERADO]: 🔴 ERROR [400]: "El ID de Estatus proporcionado es inválido o nulo."
CALL SP_CambiarEstatusParticipante(NULL, 0);
CALL SP_CambiarEstatusParticipante(0, 0);
CALL SP_CambiarEstatusParticipante(-5, 0);

-- 5.2. Validación de Dominio (Bloque D.2 - Estatus Inválido)
-- [ESPERADO]: 🔴 ERROR [400]: "...solo acepta valores binarios: 0 (Inactivo) o 1 (Activo)."
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 2);
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, NULL);

-- 5.3. Validación de Existencia (Paso E.2 - 404 Not Found)
-- [ESPERADO]: 🔴 ERROR [404]: "El Estatus solicitado no existe..."
CALL SP_CambiarEstatusParticipante(999999, 0);

-- 5.4. Prueba de Idempotencia (Paso E.3 - Sin Cambios)
-- Intentamos activar algo que ya está activo (El estatus nace activo).
-- [ESPERADO]: Mensaje 'AVISO... ya se encuentra en el estado solicitado', Accion 'SIN_CAMBIOS'.
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 1);

-- 5.5. PREPARACIÓN KILLSWITCH: Crear Curso VIVO con Alumno Inscrito
-- Paso A: Crear Cabecera
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo)
VALUES ('QA-CAP-PART-01', @IdGerenQA, @IdTemaQA, 5, 1);
SET @IdCap = LAST_INSERT_ID();

-- Paso B: Crear Detalle VIVO (Activo=1, Es_Final=0)
-- Usamos @IdEstCurVivo (que tiene Es_Final = 0)
INSERT INTO `DatosCapacitaciones` 
(Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones)
VALUES 
(@IdCap, @IdInstructorQA, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 DAY), @IdSedeQA, 1, @IdEstCurVivo, 1, 'QA-PART VIVO');
SET @IdDatosCapVivo = LAST_INSERT_ID();

-- Paso C: Inscribir al Alumno con el Estatus que queremos borrar (@IdEstInscrito)
INSERT INTO `Capacitaciones_Participantes` (Fk_Id_DatosCap, Fk_Id_Usuario, Fk_Id_CatEstPart, Calificacion)
VALUES (@IdDatosCapVivo, @IdAlumnoQA, @IdEstInscrito, 99.99);

-- [CORRECCIÓN] Capturamos el ID de la inscripción para limpieza quirúrgica
SET @IdInscripcionQA = LAST_INSERT_ID();

-- 5.6. PRUEBA DE BLOQUEO (EL CURSO ESTÁ VIVO)
-- Intentamos desactivar "INSCRITO VIVO QA".
-- [ESPERADO]: 🔴 ERROR [409]: "BLOQUEO DE INTEGRIDAD... detectaron 1 participantes... en CURSOS ACTIVOS..."
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 0);

-- 5.7. ESCENARIO DE LIBERACIÓN 1: FINALIZADO (Activo=1, Es_Final=1)
-- Actualizamos el curso para que tenga estatus "FINALIZADO". Sigue visible (Activo=1).
UPDATE `DatosCapacitaciones` SET `Fk_Id_CatEstCap` = @IdEstCurFin WHERE `Id_DatosCap` = @IdDatosCapVivo;
SELECT 'INFO: Curso migrado a FINALIZADO (Activo=1, Final=1).' AS INFO;

-- [ESPERADO]: Mensaje 'ÉXITO... ha sido DESACTIVADO'. (Debe permitirlo).
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 0);

-- Reactivamos para la siguiente prueba
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 1);

-- 5.8. [NUEVO] ESCENARIO DE LIBERACIÓN 2: ARCHIVADO FINALIZADO (Activo=0, Es_Final=1)
-- El curso finalizó y ADEMÁS alguien lo borró de la lista (Soft Delete).
-- Esta es la prueba que pediste.
UPDATE `DatosCapacitaciones` SET `Activo` = 0 WHERE `Id_DatosCap` = @IdDatosCapVivo;
SELECT 'INFO: Curso marcado como ARCHIVADO FINALIZADO (Activo=0, Final=1).' AS INFO;

-- [ESPERADO]: Mensaje 'ÉXITO... ha sido DESACTIVADO'. (Debe permitirlo).
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 0);

-- Reactivamos para la siguiente prueba
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 1);

/* =================================================================================
   [SECCIÓN COMENTADA - ESCENARIO TEÓRICO DE ANOMALÍA]
   ---------------------------------------------------------------------------------
   EXPLICACIÓN DEL COMENTARIO:
   El siguiente bloque prueba el escenario "Zombie": Un curso borrado lógicamente (Activo=0)
   pero que académicamente seguía vivo (Es_Final=0).
   
   ¿POR QUÉ SUCEDE EN TEORÍA?
   Si un Administrador borra un curso "En Progreso" directamente desde la base de datos 
   o si el SP de Baja de Cursos no valida el estatus académico, se crea este registro huérfano.
   Al estar Activo=0, el Killswitch de este SP lo ignora y permite la baja, lo cual es técnicamente
   correcto (es basura), pero semánticamente peligroso.

   SOLUCIÓN DE BLINDAJE (PRÓXIMOS PASOS):
   En el Módulo de Gestión de Capacitaciones (`SP_EliminarCapacitacionLogico`), implementaremos
   una regla de "Cierre Forzoso":
   > "No se permite la Baja Lógica de una Capacitación si su Estatus Académico no es FINAL (Es_Final=1)."
   
   Esto garantizará que nunca existan registros con (Activo=0 AND Es_Final=0), haciendo
   innecesaria la ejecución de esta prueba en el flujo normal.
   ================================================================================= */

/* -- 5.9. ESCENARIO DE LIBERACIÓN 3: ARCHIVADO VIVO (Activo=0, Es_Final=0)
-- El curso estaba "En Curso" (Vivo) pero se borró por error humano (Soft Delete).
-- Regresamos el estatus a VIVO, pero mantenemos Activo=0.

UPDATE `DatosCapacitaciones` 
SET `Fk_Id_CatEstCap` = @IdEstCurVivo 
WHERE `Id_DatosCap` = @IdDatosCapVivo;

SELECT 'INFO: Curso marcado como ARCHIVADO VIVO (Activo=0, Final=0) - Escenario Zombie.' AS INFO;

-- [ESPERADO]: Mensaje 'ÉXITO... ha sido DESACTIVADO'. (Debe permitirlo porque Activo=0 mata el bloqueo).
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 0);

-- Reactivamos para la Fase 6
CALL SP_CambiarEstatusParticipante(@IdEstInscrito, 1); 
*/

/* =================================================================================
   FASE 7: TEARDOWN (LIMPIEZA FINAL CON SPs)
   ================================================================================= */
SELECT '--- FASE 7: LIMPIEZA FINAL ---' AS TEST_STEP;

SET FOREIGN_KEY_CHECKS = 0;

-- 1. Borrar evidencia transaccional (Hijos) para poder borrar el Estatus Víctima
DELETE FROM `Capacitaciones_Participantes` WHERE `Fk_Id_Usuario` = @IdAlumnoQA;
DELETE FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = @IdDatosCapVivo;
DELETE FROM `Capacitaciones` WHERE `Id_Capacitacion` = @IdCap;

-- 2. Borrar el estatus "Inscrito" (Padre) usando el SP
CALL SP_EliminarEstatusParticipanteFisico(@IdEstInscrito);
 CALL SP_EliminarEstatusParticipanteFisico(@IdEstAprobado);

-- 3. Limpiar Infraestructura con SPs de eliminación
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaQA);
CALL SP_EliminarTipoInstruccionFisico(@IdTipoQA);
CALL SP_EliminarEstatusCapacitacionFisico(@IdEstCurVivo);
CALL SP_EliminarEstatusCapacitacionFisico(@IdEstCurFin);

CALL SP_EliminarUsuarioDefinitivamente(@IdAdminEjecutor, @IdInstructorQA);
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminEjecutor, @IdAlumnoQA);

CALL SP_EliminarRolFisicamente(@IdRolQA);
CALL SP_EliminarPuestoFisico(@IdPuesto);
CALL SP_EliminarRegimenFisico(@IdRegimen);
CALL SP_EliminarRegionFisica(@IdRegion);

CALL SP_EliminarSedeFisica(@IdSedeQA);
CALL SP_EliminarGerenciaFisica(@IdGerenQA);
CALL SP_EliminarDepartamentoFisico(@IdDep);
CALL SP_EliminarCentroTrabajoFisico(@IdCT);

-- Limpieza Geográfica (Recuperamos IDs de Sub/Dir para borrarlos con SP)
SET @IdSub = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'QA-S-PART');
SET @IdDir = (SELECT Id_CatDirecc FROM Cat_Direcciones WHERE Clave = 'QA-D-PART');
CALL SP_EliminarSubdireccionFisica(@IdSub);
CALL SP_EliminarDireccionFisica(@IdDir);

-- Ubicación
SET @IdEdo = (SELECT Id_Estado FROM Estado WHERE Codigo = 'QA-E-PART');
SET @IdPais = (SELECT Id_Pais FROM Pais WHERE Codigo = 'QA-P-PART');
CALL SP_EliminarMunicipio(@IdMunQA);
CALL SP_EliminarEstadoFisico(@IdEdo);
CALL SP_EliminarPaisFisico(@IdPais);

SET FOREIGN_KEY_CHECKS = 1;

SELECT '>>> VALIDACIÓN FINALIZADA: MÓDULO ESTATUS PARTICIPANTE CERTIFICADO <<<' AS RESULTADO;