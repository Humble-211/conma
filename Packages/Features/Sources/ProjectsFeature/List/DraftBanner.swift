            section(.jobType, missing: [.jobType, .customJobType]) {
                if let type = viewModel.draft.jobType {
                    if type == .other { Text(verbatim: viewModel.draft.customJobType ?? "") } else { Text(type.titleKey) }
                }
            }
