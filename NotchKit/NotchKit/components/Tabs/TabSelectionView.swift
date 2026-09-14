//
//  TabSelectionView.swift
//  NotchKit
//
//  Created by Hugo Persson on 2024-08-25.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

struct TabSelectionView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var presentation = NotchKitRuntime.shared.presentation
    @Namespace var animation

    private var router: NotchRouter {
        presentation.router(
            for: NotchKitRuntime.shared.displayID(for: vm.screenUUID)
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(router.availableDestinations) { destination in
                let selected = router.activeDestinationID == destination.id

                TabButton(
                    label: destination.title,
                    icon: destination.iconSystemName,
                    selected: selected
                ) {
                    withAnimation(.smooth) {
                        router.select(destination.id)
                    }
                }
                .frame(height: 26)
                .foregroundStyle(selected ? .white : .gray)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}