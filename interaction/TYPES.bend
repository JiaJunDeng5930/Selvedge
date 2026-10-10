import Base
import ./conversation/CODE.bend as Content
import ../harness/MODEL.bend as M
import ../bendlib/json.bend as J
import ../bendlib/association-map.bend as Finite
import ./INPUT.bend as U
import ./session/MODEL.bend as E
import ./presentation/MODEL.bend as View
import ./submission/FIELDS.bend as Forms
import ./services/MODEL.bend as Services

type State is Data:
  State{application: E.Application, services: Services.State}

type Input is Data:
  ApplicationInput{input: E.Input}
  ServiceInput{input: Services.Input}
  EditField{editor: U.Editor, field: Forms.Field, value: Forms.Value}
  RemoveAttachment{editor: U.Editor, id: String}

type Decision is Data:
  Decision{state: State, reply: J.Json, runtime_effects: +List<M.Effect()>,
    interaction_effects: +List<E.Effect>, service_effects: +List<Services.Effect>, durable: Bool}

type Settings is Data:
  Settings{open: Bool, access: Services.Access, credential_entered: Bool,
    appearance: Services.Appearance, open_action: Input, close_action: Input, connect_action: Input}

type Scene is Data:
  Scene{surface: View.Scene, settings: Settings,
    transfers: +List<Finite.Entry(Services.Transfer)>, preview: Services.Preview, code: +List<Content.Scene>, directory_picker: Services.DirectoryPicker}

type Control is Data:
  Control{identity: String, label: String, prominence: View.Prominence, input: Input, availability: View.Availability}
