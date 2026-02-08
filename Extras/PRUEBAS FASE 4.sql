/* =================================================================================
   FASE 4: CAMBIO DE ESTATUS, KILLSWITCH Y REGLAS DE JERARQUÍA
   ================================================================================= */
-- SELECT '--- FASE 4: KILLSWITCH Y REGLAS DE NEGOCIO ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. VALIDACIONES DE ENTRADA
-- ---------------------------------------------------------------------------------

-- 4.1. ID Inválido
CALL SP_CambiarEstatusTemaCapacitacion(0, 0);

-- 4.2. Estatus Inválido
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 5);

-- 4.3. Tema Inexistente
CALL SP_CambiarEstatusTemaCapacitacion(99999, 0);

-- ---------------------------------------------------------------------------------
-- B. PRUEBA DEL "KILLSWITCH" (Conflictos Operativos)
-- ---------------------------------------------------------------------------------

-- 4.4. Crear Cabecera de Capacitación
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo, created_at, updated_at) 
VALUES ('FOLIO-KILL-001', @IdGerenQA, @IdTemaVictima, 15, 1, NOW(), NOW());
SET @IdCapKill = LAST_INSERT_ID();

-- 4.5. Asignar Estatus "EN CURSO" (Bloqueante)
INSERT INTO `DatosCapacitaciones` (Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Observaciones, created_at, updated_at) 
VALUES (@IdCapKill, @IdInstructorQA, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 5 DAY), @IdSedeQA, @IdModalPresencial, @IdEstEnCurso, 1, 'Prueba Killswitch', NOW(), NOW()); 

-- 4.6. INTENTO DE DESACTIVACIÓN ILEGAL
-- Esperado: CONFLICTO OPERATIVO [409]
-- SELECT 'PRUEBA 4.6: Killswitch Activado (Debe Fallar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- ---------------------------------------------------------------------------------
-- C. RESOLUCIÓN DEL CONFLICTO Y DESACTIVACIÓN (Baja Lógica)
-- ---------------------------------------------------------------------------------

-- 4.7. Evolución del Curso (Liberación del Candado)
UPDATE `DatosCapacitaciones` 
SET Fk_Id_CatEstCap = @IdEstFinalizado, Observaciones = 'Curso finalizado, liberando tema', updated_at = NOW()
WHERE Fk_Id_Capacitacion = @IdCapKill AND Activo = 1;

-- 4.8. DESACTIVACIÓN EXITOSA
-- Esperado: Mensaje de éxito "DESACTIVADO".
-- SELECT 'PRUEBA 4.8: Desactivación Legal (Debe Funcionar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- Verificación:
-- SELECT Id_Cat_TemasCap, Codigo, Activo FROM Cat_Temas_Capacitacion WHERE Id_Cat_TemasCap = @IdTemaVictima;

-- ---------------------------------------------------------------------------------
-- D. VALIDACIÓN DE JERARQUÍA (Padre Inactivo)
-- ---------------------------------------------------------------------------------


-- 4.9. Simular Padre Inactivo (USANDO SP)
-- IMPORTANTE: Usamos UPDATE directo porque el SP 'SP_CambiarEstatusTipoInstruccion' 
-- nos impediría desactivar al padre debido a que 'TemaLimpio' y 'TemaUpdate' siguen activos.
-- Para esta prueba, necesitamos forzar el escenario de inconsistencia.
UPDATE Cat_Tipos_Instruccion_Cap 
SET Activo = 0 
WHERE Id_CatTipoInstCap = @IdTipoTecnico;

-- [CAMBIO V1.4]: Usamos el SP para validar que el bloqueo descendente funcione.
-- Nota: Si el SP funciona correctamente, NO debería dejarnos desactivar el Padre si tiene hijos activos.
-- Como el hijo (@IdTemaVictima) fue desactivado en el paso 4.8, el SP debería PERMITIR desactivar al padre.
CALL SP_CambiarEstatusTipoInstruccion(@IdTipoTecnico, 0);

-- 4.10. Intento de Reactivación Huérfana
-- Esperado: ERROR DE INTEGRIDAD / ERROR_JERARQUIA
-- SELECT 'PRUEBA 4.10: Validación de Jerarquía (Debe Fallar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- 4.11. Restaurar Padre
UPDATE Cat_Tipos_Instructores SET Activo = 1 WHERE Id_Cat_Tipos_Instructores = @IdTipoTecnico;

-- ---------------------------------------------------------------------------------
-- E. REACTIVACIÓN FINAL
-- ---------------------------------------------------------------------------------

-- 4.12. Reactivación Exitosa (Para pruebas posteriores)
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 1);
