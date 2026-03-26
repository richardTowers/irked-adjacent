# CM-05: Dynamic Node Forms

## Summary

Update the node create and edit UI to render form fields dynamically based on the node's content type. Instead of a fixed "body" textarea, the form renders the appropriate HTML inputs for each field defined in the content type, in position order.

## Dependencies

- **CM-03** — Content type management UI (content types must be creatable).
- **CM-04** — Node–content type association and fields column (nodes must have the `fields` column and validation).

## Requirements

### Content Type Selection (New Node)

- The new node form must include a content type selector: a dropdown listing the content types available to the selected team.
- Selecting a content type determines which fields appear in the form.
- Content type selection works without JavaScript: changing the dropdown submits a GET request with a query parameter (e.g. `GET /admin/content/new?content_type_id=3`) that reloads the form with the correct fields.
- If the team has only one content type, it should be pre-selected.

### Content Type on Edit

- The edit form displays the node's content type name but does not allow changing it.
- The form renders the fields for the node's content type, populated with the node's current field values.

### Field Type to Input Mapping

Each field definition maps to an HTML form input based on its `field_type`:

| Field Type  | HTML Input                          | Notes                              |
|-------------|-------------------------------------|------------------------------------|
| `string`    | `<input type="text">`               |                                    |
| `text`      | `<textarea>`                        | Multi-line, plain text             |
| `rich_text` | `<textarea>`                        | Same as text for now; rich editing is a future enhancement |
| `integer`   | `<input type="number" step="1">`    |                                    |
| `decimal`   | `<input type="number" step="any">`  |                                    |
| `boolean`   | `<input type="checkbox">`           |                                    |
| `date`      | `<input type="date">`               |                                    |
| `datetime`  | `<input type="datetime-local">`     |                                    |
| `reference` | `<select>`                          | Populated with eligible nodes (see below) |

### Reference Field Population

For `reference` fields, the `<select>` dropdown is populated with nodes that the user has access to (i.e. nodes belonging to teams the user is a member of). If the field definition has an `allowed_content_types` validation, only nodes of those content types are shown. Display format: node title (content type name).

### Field Ordering and Layout

- Fields are rendered in the order defined by their `position` value.
- The universal fields (`title`, `slug`, `published`) remain at the top of the form, above the content-type-specific fields. They are not part of the content type definition.
- Each field has a label (from field definition `name`), and required fields are visually marked.

### Form Submission

- Content-type-specific fields are submitted as a nested hash under `fields`: e.g. `node[fields][event_date]`, `node[fields][description]`.
- The controller permits field keys dynamically based on the content type's field definitions — not a static permit list.
- Boolean fields that are unchecked are not submitted by browsers; the controller must handle this by defaulting missing boolean fields to `false`.

### Validation Error Display

- Validation errors on content-type-specific fields must be rendered next to the corresponding input.
- Each field input must have an `id` attribute.
- Error messages must be in an element linked via `aria-describedby` on the input.
- Invalid fields must have `aria-invalid="true"`.
- A summary of all errors should appear at the top of the form (consistent with existing error display for title/slug errors).

## Acceptance Criteria

- [ ] The new node form shows a content type selector dropdown.
- [ ] Selecting a content type reloads the form with the correct fields (no JavaScript required).
- [ ] If the team has one content type, it is pre-selected.
- [ ] Each field type renders the correct HTML input.
- [ ] Fields appear in position order.
- [ ] Universal fields (title, slug, published) appear above content-type-specific fields.
- [ ] Required fields are visually marked.
- [ ] Submitting the form with valid field values creates the node successfully.
- [ ] Submitting with invalid field values shows validation errors next to the correct fields.
- [ ] The edit form shows the content type name (not editable) and renders fields with current values.
- [ ] Editing a node preserves existing field values.
- [ ] Boolean fields default to `false` when unchecked.
- [ ] Reference field dropdowns show only accessible nodes (filtered by allowed content types if configured).
- [ ] Date and datetime fields submit and display values correctly.
- [ ] Error messages are linked to inputs via `aria-describedby`.
- [ ] Invalid inputs have `aria-invalid="true"`.

## Security Considerations

- Dynamically permit only field keys that exist in the content type's field definitions — reject any extra keys submitted by the client.
- Validate all field values server-side regardless of client-side constraints (e.g. `type="number"` does not guarantee an integer reaches the server).
- Reference fields must validate that the referenced node is accessible to the current user.

## Accessibility Considerations

- Every form input must have an associated `<label>` element with a `for` attribute matching the input's `id`.
- Required fields must have `aria-required="true"` on the input and a visual indicator (e.g. asterisk with `<abbr title="required">*</abbr>`).
- Validation errors must be programmatically associated with their inputs using `aria-describedby`.
- Invalid inputs must have `aria-invalid="true"`.
- The error summary at the top of the form should use `role="alert"` or be focused after submission.
- The content type selector should have a descriptive label (e.g. "Content type").
- Field group should use `<fieldset>` and `<legend>` if semantically appropriate.

## Implementation Notes

### Rails

- Modify `Admin::ContentController` (or the existing node controller) to handle `content_type_id` in params.
- In the `new` action, load field definitions for the selected content type (from query param) and pass to the view.
- In the `create`/`update` actions, dynamically permit field keys: `params.require(:node).permit(:title, :slug, :published, :team_id, :content_type_id, fields: content_type.field_definitions.pluck(:api_key))`.
- Create a partial (e.g. `_dynamic_field.html.erb`) that renders the correct input based on `field_type`.
- For boolean fields, use a hidden field trick: `<input type="hidden" name="node[fields][is_featured]" value="false">` before the checkbox.
- Update the form partial to conditionally render content-type fields vs. the old body textarea (the old body textarea can be removed since CM-04 migrates all data).

### Rust (Actix)

- Deserialize the `fields` sub-object from form data as a `HashMap<String, serde_json::Value>`.
- Validate keys against the content type's field definitions before saving.
- Use template logic to render the correct input type for each field definition.
- Handle boolean field absence in form data.
