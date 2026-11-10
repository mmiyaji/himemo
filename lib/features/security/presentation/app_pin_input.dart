import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The four-digit app lock PIN, shared by setup and unlock.
class AppPinInput extends StatefulWidget {
  const AppPinInput({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.onSubmit,
    this.variableLength = false,
    this.label = 'PIN',
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback? onSubmit;
  final bool variableLength;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  @override
  State<AppPinInput> createState() => _AppPinInputState();
}

class _AppPinInputState extends State<AppPinInput> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FormField<String>(
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller.text),
      builder: (field) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.variableLength ? 300 : 216,
            ),
            child: SizedBox(
              width: widget.variableLength ? 300 : 216,
              height: 56,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    showCursor: false,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.transparent),
                    decoration: InputDecoration(
                      labelText: widget.label,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      labelStyle: TextStyle(color: Colors.transparent),
                      border: InputBorder.none,
                      filled: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      if (!widget.variableLength)
                        LengthLimitingTextInputFormatter(
                          4,
                          maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        ),
                    ],
                    onChanged: (value) {
                      field.didChange(value);
                      if (!widget.variableLength && value.length == 4) {
                        widget.onSubmit?.call();
                      }
                    },
                    onSubmitted: (value) {
                      if (widget.variableLength || value.length == 4) {
                        widget.onSubmit?.call();
                      }
                    },
                  ),
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          widget.controller,
                          _focusNode,
                        ]),
                        builder: (context, _) {
                          final value = widget.controller.value;
                          final slots = widget.variableLength
                              ? value.text.length.clamp(4, 8)
                              : 4;
                          final cursor = value.selection.isValid
                              ? value.selection.extentOffset.clamp(0, slots - 1)
                              : value.text.length.clamp(0, slots - 1);
                          return Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: 56.0 * slots - 8,
                              height: 56,
                              child: Row(
                                children: [
                                  for (var i = 0; i < slots; i++) ...[
                                    if (i != 0) const SizedBox(width: 8),
                                    Expanded(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color:
                                              _focusNode.hasFocus && i == cursor
                                              ? colors.primaryContainer
                                                    .withValues(alpha: 0.3)
                                              : null,
                                          border:
                                              _focusNode.hasFocus && i == cursor
                                              ? Border.all(
                                                  color: colors.primary,
                                                  width: 2,
                                                )
                                              : Border.all(
                                                  color: colors.outlineVariant,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Center(
                                          child: i == 7 && value.text.length > 8
                                              ? FittedBox(
                                                  child: Text(
                                                    '+${value.text.length - 7}',
                                                  ),
                                                )
                                              : i < value.text.length
                                              ? Icon(
                                                  Icons.circle,
                                                  size: 10,
                                                  color: colors.primary,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (field.errorText case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ),
        ],
      ),
    );
  }
}
