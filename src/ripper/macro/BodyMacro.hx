package ripper.macro;

#if macro
using sneaker.format.StringExtension;
using sneaker.macro.FieldExtension;
using sneaker.macro.ClassTypeExtension;
using ripper.macro.utility.ClassTypeExtension;

import haxe.macro.ExprTools;
import haxe.macro.Type.ClassType;
import ripper.macro.utility.ContextTools;
	#if !ripper_validation_disable
	import ripper.macro.utility.ExprExtension.validateDomainName;
	#end

class BodyMacro {
	static final spiritsMetadataName = ":ripper.spirits";
	static final overrideMetadataName = ":ripper.override";
	static final spiritInterfaceName = "ripper.Spirit";

	/**
		A build macro that is run for each `Body` classes.
		Copies fields from `Spirit` classes that are specified by the `@:spirits` metadata.
	**/
	macro public static function build(): Null<Fields> {
		debug('Start to build Body class.');

		final localClassRef = Context.getLocalClass();
		if (localClassRef == null) {
			warn('Tried to build something that is not a class.');
			debug('Go to next.');
			return null;
		}

		final localClassName = localClassRef.toString();
		final localClass = localClassRef.get();
		final metadataArray = localClass.meta.extract(spiritsMetadataName);

		if (metadataArray.length == 0) {
			#if !ripper_validation_disable
			if (!localClass.anySuperClassHasMetadata(spiritsMetadataName))
				warn('Marked as Body but missing @${spiritsMetadataName} metadata for specifying classes from which to copy fields.');
			#end

			debug('No @${spiritsMetadataName} metadata. End building.');
			return null;
		}

		final result: Null<Fields> = processAllMetadata(
			localClassName,
			metadataArray
		);

		debug('End building.');
		return result;
	}

	/**
		Extract the class instance from `type`.
		This process is necessary for invoking the build macro of `type` if not yet called.
	**/
	static function resolveClass(type: MacroType, typeName: String): Null<ClassType> {
		try {
			final classType = TypeTools.getClass(type);
			return classType;
		} catch (e:Dynamic) {
			return null;
		}
	}

	/**
		@return `Field` object that has the same name as `name`. `null` if not found.
	**/
	static function findFieldIn(fields: Array<Field>, name: String): Null<Field> {
		var found: Null<Field> = null;
		for (i in 0...fields.length) {
			final field = fields[i];
			if (field.name != name) continue;
			found = field;
			break;
		}
		return found;
	}

	/**
		Parse a metadata parameter as a class name,
		and adds the fields of that class to `localFields`.
	**/
	static function processMetadataParameter(
		parameter: Expr,
		parameterString: String,
		localFields: Array<Field>
	): MetadataParameterProcessResult {
		#if !ripper_validation_disable
		final validated = validateDomainName(parameter);
		if (validated == null) return InvalidType;
		#end

		debug('Start to search type: ${parameterString}');

		final type = ContextTools.findClassyType(parameterString);
		#if !ripper_validation_disable
		if (type == null) return NotFound;
		#end

		final fullTypeName = TypeTools.toString(type);
		debug('Found type: ${fullTypeName}');
		debug('Resolving as a class.');
		final classType = resolveClass(type, fullTypeName);

		#if !ripper_validation_disable
		if (classType == null) return NotClass;
		if (!classType.implementsInterface(spiritInterfaceName)) return NotSpirit;
		#end

		debug('Resolved type as a class: ${classType.name}');
		debug('Copying fields...');
		final fields = SpiritMacro.fieldsMap.get(fullTypeName);

		#if !ripper_validation_disable
		if (fields == null) return NotRegistered;
		if (fields.length == 0) return NoFields;
		#end

		for (field in fields) {
			debug('  - ${field.name}');

			final sameNameField = findFieldIn(localFields, field.name);
			if (sameNameField != null) {
				#if ripper_validation_disable
				debug('    Override field.');
				localFields.remove(sameNameField);
				#else
				if (field.hasMetadata(overrideMetadataName)) {
					debug('    Override field.');
					localFields.remove(sameNameField);
				} else {
					warn('    Duplicate field name: ${field.name}');
					continue;
				}
				#end
			}

			final copyingField = Reflect.copy(field);
			copyingField.pos = Context.currentPos();
			localFields.push(copyingField);
		}

		return Success;
	}

	/**
		Process the given metadata array and calls `processMetadataParameter()` for each parameter.
	**/
	static function processAllMetadata(
		localClassName: String,
		metadataArray: Array<MetadataEntry>
	): Null<Fields> {
		final localFields = Context.getBuildFields();

		for (metadata in metadataArray) {
			final metadataParameters = metadata.params;
			#if !ripper_validation_disable
			if (metadataParameters == null) {
				warn("Found metadata without arguments.");
				debug('Go to next.');
				continue;
			}
			#end
			for (parameter in metadataParameters) {
				final typeName = ExprTools.toString(parameter);
				debug('Start to process metadata parameter: ${typeName}');
				final result = processMetadataParameter(
					parameter,
					typeName,
					localFields
				);

				switch result {
					case InvalidType:
						warn('Invalid type name: ${typeName}');
					case NotFound:
						warn('Type not found: ${typeName}');
					case NotClass:
						warn('Not a class: ${typeName}');
					case NotSpirit:
						warn('Specified by metadata but does not implement ripper.Spirit: $typeName');
					case NotRegistered:
						warn('Fields not registered: ${typeName} ... Try restarting completion server.');
					case NoFields:
						debug('No fields in class: ${typeName}');
					case Success:
						#if !ripper_validation_disable
						info('Copied fields: ${localClassName.sliceAfterLastDot()} <= ${typeName.sliceAfterLastDot()}');
						#else
						info('Processed metadata parameter: ${typeName}');
						#end
				}
			}
		}

		return localFields;
	}
}

/**
	Kind of result that `BodyMacro.processMetadataParameter()` returns.
**/
private enum MetadataParameterProcessResult {
	InvalidType;
	NotFound;
	NotClass;
	NotSpirit;
	NotRegistered;
	NoFields;
	Success;
}
#end
