//
//  HomeView.swift
//  Manga-Reader
//
//  Created by Elias Magdaleno on 10/2/25.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24){

                    // show progress indicator when loading
                    if vm.isLoading{
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let err  = vm.errorMessage{
                        Text("Error: \(err)").foregroundStyle(.red)
                    }

                    SectionHeader("Popular")
                    MangaRail(items: vm.popular)
                    SectionHeader("Recently Updated")
                    MangaRail(items: vm.latestUpdates.map { $0.manga })
                    SectionHeader("Newly Added")
                    MangaRail(items: vm.newTitles)


                }
                .padding(.vertical, 16)
            }
            .task { vm.loadHome()}
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String){
        self.title = title
    }
    var body: some View {
        Text(title).font(.title2).bold()
    }
}



                
            

#Preview {
    HomeView()
}
