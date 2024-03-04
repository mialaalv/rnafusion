/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_rnafusion_pipeline'
include { paramsSummaryLog; paramsSummaryMap } from 'plugin/nf-validation'




// Check mandatory parameters


// //TODO: move this to utils_nf_core_rnafusion_pipeline
// if (file(params.input).exists() || params.build_references) { ch_input = file(params.input) } else { exit 1, 'Input samplesheet does not exist or was not specified!' }
// if (params.fusioninspector_only && !params.fusioninspector_fusions) { exit 1, 'Parameter --fusioninspector_fusions PATH_TO_FUSION_LIST expected with parameter --fusioninspector_only'}
// if (params.tools_cutoff < 1) { exit 1, 'Parameter: --tools_cutoff should be >= 1'}


ch_chrgtf = params.starfusion_build ? Channel.fromPath(params.chrgtf).map { it -> [[id:it.Name], it] }.collect() : Channel.fromPath("${params.starfusion_ref}/ref_annot.gtf").map { it -> [[id:it.Name], it] }.collect()
ch_starindex_ref = params.starfusion_build ? Channel.fromPath(params.starindex_ref).map { it -> [[id:it.Name], it] }.collect() : Channel.fromPath("${params.starfusion_ref}/ref_genome.fa.star.idx").map { it -> [[id:it.Name], it] }.collect()
ch_starindex_ensembl_ref = Channel.fromPath(params.starindex_ref).map { it -> [[id:it.Name], it] }.collect()
ch_refflat = params.starfusion_build ? Channel.fromPath(params.refflat).map { it -> [[id:it.Name], it] }.collect() : Channel.fromPath("${params.ensembl_ref}/ref_annot.gtf.refflat").map { it -> [[id:it.Name], it] }.collect()
ch_rrna_interval = params.starfusion_build ?  Channel.fromPath(params.rrna_intervals).map { it -> [[id:it.Name], it] }.collect() : Channel.fromPath("${params.ensembl_ref}/ref_annot.interval_list").map { it -> [[id:it.Name], it] }.collect()
ch_fusionreport_ref = Channel.fromPath(params.fusionreport_ref).map { it -> [[id:it.Name], it] }.collect()
ch_arriba_ref_blacklist = Channel.fromPath(params.arriba_ref_blacklist).map { it -> [[id:it.Name], it] }.collect()
ch_arriba_ref_known_fusions = Channel.fromPath(params.arriba_ref_known_fusions).map { it -> [[id:it.Name], it] }.collect()
ch_arriba_ref_protein_domains = Channel.fromPath(params.arriba_ref_protein_domains).map { it -> [[id:it.Name], it] }.collect()
ch_arriba_ref_cytobands = Channel.fromPath(params.arriba_ref_cytobands).map { it -> [[id:it.Name], it] }.collect()
ch_hgnc_ref = Channel.fromPath(params.hgnc_ref).map { it -> [[id:it.Name], it] }.collect()
ch_hgnc_date = Channel.fromPath(params.hgnc_date).map { it -> [[id:it.Name], it] }.collect()
ch_fasta = Channel.fromPath(params.fasta).map { it -> [[id:it.Name], it] }.collect()
ch_gtf = Channel.fromPath(params.gtf).map { it -> [[id:it.Name], it] }.collect()
ch_transcript = Channel.fromPath(params.transcript).map { it -> [[id:it.Name], it] }.collect()
ch_fai = Channel.fromPath(params.fai).map { it -> [[id:it.Name], it] }.collect()

// def checkPathParamList = [
//     params.fasta,
//     params.fai,
//     params.gtf,
//     params.transcript,
// ]

// for (param in checkPathParamList) if ((param) && !params.build_references) file(param, checkIfExists: true)
// def params_fasta_path_uri = params.fasta =~ /^([a-zA-Z0-9]*):\/\/(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)$/
// // check if params.fasta is a remote uri such as s3://, gs:// or dx://
// if (params_fasta_path_uri){
//     log.info "INFO: a remote uri path detected, check for absolute path and trailing '/' not performed"
//     // log.info "INFO:  remote uri path detected (e.g. s3), check for absolute path and trailing '/' not performed"
// }
// else {
//     for (param in checkPathParamList) if ((param.toString())!= file(param).toString() && !params.build_references) { exit 1, "Problem with ${param}: ABSOLUTE PATHS are required! Check for trailing '/' at the end of paths too." }
// }


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//

include { TRIM_WORKFLOW                 }   from '../subworkflows/local/trim_workflow'
include { ARRIBA_WORKFLOW               }   from '../subworkflows/local/arriba_workflow'
include { QC_WORKFLOW                   }   from '../subworkflows/local/qc_workflow'
include { STARFUSION_WORKFLOW           }   from '../subworkflows/local/starfusion_workflow'
include { STRINGTIE_WORKFLOW            }   from '../subworkflows/local/stringtie_workflow'
include { FUSIONCATCHER_WORKFLOW        }   from '../subworkflows/local/fusioncatcher_workflow'
include { FUSIONINSPECTOR_WORKFLOW      }   from '../subworkflows/local/fusioninspector_workflow'
include { FUSIONREPORT_WORKFLOW         }   from '../subworkflows/local/fusionreport_workflow'
include { validateInputSamplesheet      }   from '../subworkflows/local/utils_nfcore_rnafusion_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { CAT_FASTQ                   } from '../modules/nf-core/cat/fastq/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RNAFUSION {

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // Create channel from input file provided through params.input
    //
    Channel
        .fromSamplesheet("input")
        .map {
            meta, fastq_1, fastq_2 ->
                if (!fastq_2) {
                    return [ meta.id, meta + [ single_end:true ], [ fastq_1 ] ]
                } else {
                    return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ] ]
                }
        }
        .groupTuple()
        .map {
            validateInputSamplesheet(it)
        }
        .branch {
            meta, fastqs ->
                single  : fastqs.size() == 1
                    return [ meta, fastqs.flatten() ]
                multiple: fastqs.size() > 1
                    return [ meta, fastqs.flatten() ]
        }
        .set { ch_fastq }

    //
    // MODULE: Concatenate FastQ files from same sample if required
    //
    CAT_FASTQ (
        ch_fastq.multiple
    )
    .reads
    .mix(ch_fastq.single)
    .set { ch_cat_fastq }
    ch_versions = ch_versions.mix(CAT_FASTQ.out.versions)

    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_cat_fastq
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]})
    ch_versions = ch_versions.mix(FASTQC.out.versions)

    TRIM_WORKFLOW (
        ch_cat_fastq
    )
    ch_reads_fusioncatcher = TRIM_WORKFLOW.out.ch_reads_fusioncatcher
    ch_reads_all = TRIM_WORKFLOW.out.ch_reads_all
    ch_versions = ch_versions.mix(TRIM_WORKFLOW.out.versions)

    //
    // SUBWORKFLOW:  Run STAR alignment and Arriba
    //

    ARRIBA_WORKFLOW (
        ch_reads_all,
        ch_gtf,
        ch_fasta,
        ch_starindex_ensembl_ref,
        ch_arriba_ref_blacklist,
        ch_arriba_ref_known_fusions,
        ch_arriba_ref_protein_domains
    )
    ch_versions = ch_versions.mix(ARRIBA_WORKFLOW.out.versions)


//Run STAR fusion
    STARFUSION_WORKFLOW (
        ch_reads_all,
        ch_chrgtf,
        ch_starindex_ref,
        ch_fasta
    )
    ch_versions = ch_versions.mix(STARFUSION_WORKFLOW.out.versions)


//Run fusioncatcher
    FUSIONCATCHER_WORKFLOW (
        ch_reads_fusioncatcher
    )
    ch_versions = ch_versions.mix(FUSIONCATCHER_WORKFLOW.out.versions)


//Run stringtie
    STRINGTIE_WORKFLOW (
        STARFUSION_WORKFLOW.out.ch_bam_sorted,
        ch_chrgtf
    )
    ch_versions = ch_versions.mix(STRINGTIE_WORKFLOW.out.versions)


    //Run fusion-report
    FUSIONREPORT_WORKFLOW (
        ch_reads_all,
        ch_fusionreport_ref,
        ARRIBA_WORKFLOW.out.fusions,
        STARFUSION_WORKFLOW.out.fusions,
        FUSIONCATCHER_WORKFLOW.out.fusions
    )
    ch_versions = ch_versions.mix(FUSIONREPORT_WORKFLOW.out.versions)


    //Run fusionInpector
    FUSIONINSPECTOR_WORKFLOW (
        ch_reads_all,
        FUSIONREPORT_WORKFLOW.out.fusion_list,
        FUSIONREPORT_WORKFLOW.out.fusion_list_filtered,
        FUSIONREPORT_WORKFLOW.out.report,
        FUSIONREPORT_WORKFLOW.out.csv,
        STARFUSION_WORKFLOW.out.ch_bam_sorted_indexed,
        ch_chrgtf,
        ch_arriba_ref_protein_domains,
        ch_arriba_ref_cytobands,
        ch_hgnc_ref,
        ch_hgnc_date
    )
    ch_versions = ch_versions.mix(FUSIONINSPECTOR_WORKFLOW.out.versions)


    //QC
    QC_WORKFLOW (
        STARFUSION_WORKFLOW.out.ch_bam_sorted,
        STARFUSION_WORKFLOW.out.ch_bam_sorted_indexed,
        ch_chrgtf,
        ch_refflat,
        ch_fasta,
        ch_fai,
        ch_rrna_interval
    )
    ch_versions = ch_versions.mix(QC_WORKFLOW.out.versions)

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(storeDir: "${params.outdir}/pipeline_info", name: 'nf_core_pipeline_software_mqc_versions.yml', sort: true, newLine: true)
        .set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config                     = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config              = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
    ch_multiqc_logo                       = params.multiqc_logo ? Channel.fromPath(params.multiqc_logo, checkIfExists: true) : Channel.empty()
    summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary                   = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = Channel.empty()
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: false))
    ch_multiqc_files                      = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(TRIM_WORKFLOW.out.ch_fastp_html.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(TRIM_WORKFLOW.out.ch_fastp_json.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(TRIM_WORKFLOW.out.ch_fastqc_trimmed.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(STARFUSION_WORKFLOW.out.star_stats.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(STARFUSION_WORKFLOW.out.star_gene_count.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(QC_WORKFLOW.out.rnaseq_metrics.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(QC_WORKFLOW.out.duplicate_metrics.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(QC_WORKFLOW.out.insertsize_metrics.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files                      = ch_multiqc_files.mix(FUSIONINSPECTOR_WORKFLOW.out.ch_arriba_visualisation.collect{it[1]}.ifEmpty([]))

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
