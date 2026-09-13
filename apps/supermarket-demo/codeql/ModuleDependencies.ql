/**
 * Dépendances de code directes des modules applicatifs vers le module de
 * contrats partagé. Les dépendances Maven seules ne suffisent pas : cette
 * requête prouve qu'un type du module est réellement référencé par le code.
 */
import java

from ImportType importDeclaration, CompilationUnit source, ClassOrInterface imported
where
  source = importDeclaration.getCompilationUnit() and
  imported = importDeclaration.getImportedType() and
  source.getRelativePath().regexpMatch("(order-service|inventory-service|restock-service)/src/main/java/.*") and
  imported.getCompilationUnit().getRelativePath().matches("supermarket-contracts/src/main/java/%")
select
  source.getRelativePath(),
  importDeclaration.getLocation().getStartLine(),
  imported.getQualifiedName(),
  imported.getCompilationUnit().getRelativePath()
