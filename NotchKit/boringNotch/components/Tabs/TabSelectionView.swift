//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var router = NotchKitRuntime.shared.router
    @Namespace var animation

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